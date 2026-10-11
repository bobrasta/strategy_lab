import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import '../chart/indicator_layer.dart';
import '../engine/engine_service.dart';
import '../state/app_state.dart';
import '../state/lab_state.dart' show InputSpec, StrategyInfo;
import '../state/settings.dart';
import 'indicator_output.dart';

// Top-level so the isolate closure captures only its arguments.
Future<IndicatorOutput> _loadIso(String dir, List<PlotSpec> declared) => Isolate.run(() => loadIndicatorOutput(dir, declared: declared));

/// `indicator_inputs` → `{schema, plots}`: the input schema (as `hummer inputs` prints it, or
/// just its `inputs` list) and the declared plots.
class IndicatorSchema {
  IndicatorSchema(this.inputs, this.plots);

  factory IndicatorSchema.fromJson(Map r) {
    final sc = r['schema'];
    final list = sc is List ? sc : (sc is Map ? sc['inputs'] : r['inputs']);
    final pl = r['plots'] ?? (sc is Map ? sc['plots'] : null);
    return IndicatorSchema(
      [for (final i in (list as List?) ?? const []) InputSpec(i as Map)],
      [if (pl is List) for (var i = 0; i < pl.length; i++) if (pl[i] is Map) PlotSpec.fromJson(pl[i] as Map, i)],
    );
  }

  final List<InputSpec> inputs;
  final List<PlotSpec> plots;
}

/// One indicator attached to the chart. Several can share an indicator (different or equal inputs).
class IndicatorInstance {
  IndicatorInstance(this.uid, this.name, Map<String, String> inputs, {this.visible = true}) : inputs = {...inputs};

  final int uid;
  final String name;

  /// Only the inputs that differ from the indicator's defaults (as in the Tester).
  Map<String, String> inputs;
  bool visible;
  String label = '';

  /// idle (waiting for a chart or the engine) / starting / queued / running / loading / ok / failed / stopped
  String state = 'idle';
  String stage = '', simTime = '';
  double pct = 0;
  String? jobId, out, error, signal;
  int? exitCode;
  bool cached = false;
  List<String> journalTail = const [], stderrTail = const [];

  /// The data file the current computation or [output] is for.
  String? dataFile;
  IndicatorOutput? output;

  /// Bumped by every (re)compute and by removal, so a late answer for an older job is dropped.
  int gen = 0;
  bool removed = false;

  late final IndicatorLayer layer = IndicatorLayer(this);

  bool get active => const {'starting', 'queued', 'running', 'loading'}.contains(state);

  /// One line for the panel and the Layers rail.
  String get status => switch (state) {
        'idle' => 'Waits for a chart and the engine',
        'starting' => 'Starting…',
        'queued' => 'Queued…',
        'running' => stage == 'loading' || pct <= 0 ? 'Loading data…' : 'Computing ${pct.toStringAsFixed(1)} %${simTime.isEmpty ? '' : ' · $simTime'}',
        'loading' => 'Reading the output…',
        'ok' => output == null
            ? 'Done'
            : [
                if (output!.plots.isNotEmpty || output!.plotRecords > 0) '${_n(output!.plotRecords)} plot values',
                if (output!.drawings.lives > 0) '${_n(output!.drawings.lives)} objects',
                if (cached) 'cached',
              ].join(' · '),
        'stopped' => 'Stopped',
        _ => 'Failed${error == null || error!.isEmpty ? '' : ': $error'}${signal == null ? '' : ' · $signal'}${exitCode == null || signal != null ? '' : ' · exit code $exitCode'}',
      };

  static String _n(int v) {
    final s = '$v', b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }
}

/// The inputs form being filled in: adding [name], or editing [instance].
class IndicatorDraft {
  IndicatorDraft(this.name, this.instance, Map<String, String> values) : values = {...values};
  final String name;
  final IndicatorInstance? instance;

  /// Non-default values only.
  final Map<String, String> values;

  String value(InputSpec s) => values[s.name] ?? s.def;
  void set(InputSpec s, String v) => v == s.def ? values.remove(s.name) : values[s.name] = v;
}

/// The label MT5 shows for an attached indicator: its name and the inputs that differ from the
/// defaults, e.g. `fvg (M15, 0.10)`. In schema order when the schema is known.
String indicatorLabel(String name, Map<String, String> inputs, IndicatorSchema? schema) {
  final vals = schema == null
      ? inputs.values.toList()
      : [
          for (final s in schema.inputs)
            if (inputs.containsKey(s.name) && inputs[s.name] != s.def) inputs[s.name]!,
          for (final e in inputs.entries)
            if (!schema.inputs.any((s) => s.name == e.key)) e.value,
        ];
  return vals.isEmpty ? name : '$name (${vals.join(', ')})';
}

bool isUnknownMethod(EngineError e) => e.code == 'unknown_method' || e.message.contains('unknown method');

/// MT5's Navigator → Indicators and the indicators attached to the chart (SPEC §7.7, §14 M7).
/// Values are computed by the engine (`start_indicator`, cached per inputs and data); this class
/// only starts jobs, follows their events and reads their output folders off the UI isolate.
class IndicatorsState extends ChangeNotifier {
  IndicatorsState({required this.engine, required this.chart, required this.settings}) {
    for (final s in settings.indicators) {
      final i = IndicatorInstance(++_uid, s.name, s.inputs, visible: s.visible);
      i.label = indicatorLabel(i.name, i.inputs, null);
      instances.add(i);
    }
    _chartPath = chart.candlesPath;
    chart.addListener(_onChart);
    _publish();
  }

  static const kUnsupported = 'This engine has no indicator support. Use Build engine, or update the engine.';

  final EngineService engine;
  final AppState chart;
  final Settings settings;

  /// From `list_indicators` (indicators/*.cpp): name, status built / stale / not_built.
  List<StrategyInfo> list = const [];
  bool listed = false;

  /// Set when the engine answers the indicator methods with "unknown method" (an engine before M7).
  String? unsupported;
  String? listError;

  final Map<String, IndicatorSchema> schemas = {};
  final Map<String, String> schemaErrors = {};
  final List<IndicatorInstance> instances = [];
  IndicatorDraft? draft;

  int _uid = 0;
  final Map<String, IndicatorInstance> _jobs = {};

  /// Events that arrived before start_indicator's response was handled (same stdout chunk).
  final Map<String, List<Map<String, dynamic>>> _early = {};

  /// Parsed outputs by folder: identical instances share one.
  final Map<String, IndicatorOutput> _outputs = {};
  final Map<String, Future<IndicatorOutput>> _reading = {};
  String? _chartPath;
  bool _disposed = false;

  IndicatorSchema? schemaOf(String name) => schemas[name];
  StrategyInfo? infoOf(String name) => list.where((x) => x.name == name).firstOrNull;

  // ── list, schema ────────────────────────────────────────────────────
  Future<void> refresh() async {
    if (!engine.ready) return;
    try {
      final r = await engine.request('list_indicators');
      list = [for (final x in (r as List)) StrategyInfo(x as Map)];
      listed = true;
      unsupported = null;
      listError = null;
    } on EngineError catch (e) {
      if (isUnknownMethod(e)) {
        unsupported = kUnsupported;
      } else if (e.code != 'not_running' && e.code != 'engine_exited') {
        listError = e.message;
      }
    } catch (e) {
      listError = '$e';
    }
    _notify();
  }

  Future<IndicatorSchema?> loadSchema(String name) async {
    try {
      final r = (await engine.request('indicator_inputs', {'name': name})) as Map;
      final sc = IndicatorSchema.fromJson(r);
      schemas[name] = sc;
      schemaErrors.remove(name);
      for (final i in instances.where((i) => i.name == name)) {
        i.label = indicatorLabel(name, i.inputs, sc);
      }
      _publish();
      return sc;
    } on EngineError catch (e) {
      if (isUnknownMethod(e)) unsupported = kUnsupported;
      schemaErrors[name] = e.message;
    } catch (e) {
      schemaErrors[name] = '$e';
    }
    _notify();
    return null;
  }

  /// After a build of [name]: its inputs may have changed and its attached instances recompute.
  void onBuilt(String name, bool ok) {
    schemas.remove(name);
    schemaErrors.remove(name);
    unawaited(refresh().then((_) async {
      if (!ok) return;
      if (instances.any((i) => i.name == name) || draft?.name == name) await loadSchema(name);
      for (final i in instances.where((i) => i.name == name)) {
        unawaited(_start(i));
      }
    }));
  }

  // ── the inputs form ─────────────────────────────────────────────────
  Future<void> openEditor(String name, {IndicatorInstance? instance}) async {
    draft = IndicatorDraft(name, instance, instance?.inputs ?? const {});
    _notify();
    if (!schemas.containsKey(name)) await loadSchema(name);
  }

  void closeEditor() {
    draft = null;
    _notify();
  }

  void setDraft(InputSpec s, String v) {
    draft?.set(s, v);
    _notify();
  }

  void resetDraft() {
    draft?.values.clear();
    _notify();
  }

  /// The form's problems in the user's words (empty = it can be applied).
  List<String> draftProblems() {
    final d = draft;
    if (d == null) return const [];
    final sc = schemas[d.name];
    if (sc == null) return [schemaErrors[d.name] ?? 'Reading inputs…'];
    return [
      for (final s in sc.inputs)
        if (s.check(d.value(s)) case final e?) '${s.name}: $e.',
    ];
  }

  /// Adds the draft's indicator to the chart, or applies the new inputs to the edited instance.
  void applyDraft() {
    final d = draft;
    if (d == null || draftProblems().isNotEmpty) return;
    draft = null;
    final i = d.instance;
    if (i == null || i.removed) {
      add(d.name, d.values);
    } else {
      setInputs(i, d.values);
    }
  }

  // ── instances ───────────────────────────────────────────────────────
  IndicatorInstance add(String name, Map<String, String> inputs) {
    final i = IndicatorInstance(++_uid, name, inputs)..label = indicatorLabel(name, inputs, schemas[name]);
    instances.add(i);
    _persist();
    unawaited(_start(i));
    return i;
  }

  void setInputs(IndicatorInstance i, Map<String, String> inputs) {
    i.inputs = {...inputs};
    i.label = indicatorLabel(i.name, i.inputs, schemas[i.name]);
    i.output = null; // the old values belong to the old inputs
    _persist();
    unawaited(_start(i));
  }

  void remove(IndicatorInstance i) {
    i.removed = true;
    i.gen++;
    _forgetJob(i);
    instances.remove(i);
    if (draft?.instance == i) draft = null;
    _pruneOutputs();
    _persist();
  }

  void setVisible(IndicatorInstance i, bool v) {
    i.visible = v;
    _persist();
  }

  /// Computes every instance that has nothing for the chart's data file (startup, a new data
  /// file, an engine restart). The engine's cache makes repeats cheap.
  void syncAll() {
    for (final i in [...instances]) {
      if (i.active || (i.state == 'ok' && i.dataFile == chart.candlesPath && i.output != null)) continue;
      unawaited(_start(i));
    }
  }

  /// Retries one instance (after a failure).
  void recompute(IndicatorInstance i) => unawaited(_start(i));

  void _onChart() {
    final p = chart.candlesPath;
    if (p == _chartPath) return;
    _chartPath = p;
    for (final i in instances) {
      if (i.dataFile != p) {
        i.gen++;
        _forgetJob(i);
        i
          ..output = null
          ..dataFile = null
          ..state = 'idle';
      }
    }
    _pruneOutputs();
    _publish();
    if (p != null) syncAll();
  }

  Future<void> _start(IndicatorInstance i) async {
    final path = chart.candlesPath;
    if (i.removed || path == null || !engine.ready || unsupported != null) return;
    _forgetJob(i);
    final gen = ++i.gen;
    if (i.dataFile != path) i.output = null;
    i
      ..dataFile = path
      ..state = 'starting'
      ..pct = 0
      ..stage = ''
      ..simTime = ''
      ..error = null
      ..signal = null
      ..exitCode = null
      ..cached = false
      ..journalTail = const []
      ..stderrTail = const [];
    _publish();
    try {
      final r = (await engine.request('start_indicator', {
        'indicator': i.name,
        'data': path,
        'inputs': i.inputs,
        'profile': settings.profilePath,
      })) as Map;
      final job = '${r['job_id']}';
      if (gen != i.gen) {
        unawaited(_stopJob(job));
        return;
      }
      i
        ..jobId = job
        ..out = r['out'] as String?
        ..cached = r['cached'] == true;
      _jobs[job] = i;
      for (final e in _early.remove(job) ?? const <Map<String, dynamic>>[]) {
        onEvent(e);
      }
    } on EngineError catch (e) {
      if (gen != i.gen) return;
      if (isUnknownMethod(e)) {
        unsupported = kUnsupported;
        i.state = 'idle';
      } else {
        i
          ..state = 'failed'
          ..error = e.message;
      }
    } catch (e) {
      if (gen != i.gen) return;
      i
        ..state = 'failed'
        ..error = '$e';
    }
    _publish();
  }

  void _forgetJob(IndicatorInstance i) {
    final j = i.jobId;
    i.jobId = null;
    if (j == null) return;
    if (_jobs.remove(j) != null) unawaited(_stopJob(j));
  }

  Future<void> _stopJob(String job) async {
    try {
      await engine.request('stop_indicator', {'job_id': job});
    } catch (_) {
      // already finished, or the engine is gone
    }
  }

  // ── engine events ───────────────────────────────────────────────────
  void onEvent(Map<String, dynamic> e) {
    final ev = '${e['event']}';
    if (ev == 'engine_exited') {
      for (final i in instances.where((i) => i.active && i.state != 'loading')) {
        i
          ..state = 'failed'
          ..error = 'The engine stopped.';
      }
      _jobs.clear();
      _publish();
      return;
    }
    if (!ev.startsWith('indicator_')) return;
    final id = '${e['job_id']}';
    final i = _jobs[id];
    if (i == null) {
      if (_early.length > 20) _early.remove(_early.keys.first);
      _early.putIfAbsent(id, () => []).add(e);
      return;
    }
    switch (ev) {
      case 'indicator_queued':
        i.state = 'queued';
      case 'indicator_started':
        i.state = 'running';
        i.out = (e['out'] as String?) ?? i.out;
      case 'indicator_progress':
        i.state = 'running';
        i.pct = (e['pct'] as num?)?.toDouble() ?? i.pct;
        i.simTime = '${e['sim_time'] ?? i.simTime}';
        i.stage = '${e['stage'] ?? (e['pct'] != null ? 'running' : i.stage)}';
      case 'indicator_finished':
        _jobs.remove(id);
        i.jobId = null;
        unawaited(_finished(i, e));
        return;
    }
    _publish();
  }

  Future<void> _finished(IndicatorInstance i, Map<String, dynamic> e) async {
    final status = '${e['status']}';
    i
      ..out = (e['out'] as String?) ?? i.out
      ..cached = e['cached'] == true || i.cached;
    if (status != 'ok') {
      i
        ..state = status == 'stopped' ? 'stopped' : 'failed'
        ..error = e['error'] as String?
        ..signal = e['signal'] as String?
        ..exitCode = (e['exit_code'] as num?)?.toInt()
        ..journalTail = [for (final l in (e['journal_tail'] as List?) ?? const []) '$l']
        ..stderrTail = [for (final l in (e['stderr_tail'] as List?) ?? const []) '$l'];
      _publish();
      return;
    }
    await _load(i);
  }

  Future<void> _load(IndicatorInstance i) async {
    final out = i.out, gen = i.gen;
    if (out == null || out.isEmpty) {
      i
        ..state = 'failed'
        ..error = 'The engine named no output folder.';
      _publish();
      return;
    }
    var o = _outputs[out];
    if (o == null) {
      i.state = 'loading';
      _publish();
      try {
        // Identical instances finishing together read the folder once.
        o = await (_reading[out] ??= _loadIso(out, schemas[i.name]?.plots ?? const []).whenComplete(() {
          _reading.remove(out); // (a block: whenComplete would wait on the returned future, this one)
        }));
      } catch (e) {
        if (gen != i.gen) return;
        i
          ..state = 'failed'
          ..error = e is IndicatorLoadError ? e.message : "The output in $out couldn't be read: $e";
        _publish();
        return;
      }
      _outputs[out] = o;
    }
    if (gen != i.gen || i.removed) return;
    i
      ..output = o
      ..state = 'ok';
    _pruneOutputs();
    _publish();
  }

  void _pruneOutputs() => _outputs.removeWhere((k, _) => !instances.any((i) => i.out == k || i.output?.dir == k));

  // ── plumbing ────────────────────────────────────────────────────────
  void _persist() {
    settings.indicators = [for (final i in instances) IndicatorSetting(i.name, i.inputs, visible: i.visible)];
    settings.changed();
    _publish();
  }

  /// Hands the layers to the chart (which repaints) and updates the panel.
  void _publish() {
    if (_disposed) return;
    chart.setIndicatorLayers([for (final i in instances) i.layer]);
    notifyListeners();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    chart.removeListener(_onChart);
    super.dispose();
  }
}
