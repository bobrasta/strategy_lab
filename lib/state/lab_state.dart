import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';

import '../chart/volume_profile_tool.dart';
import '../practice/practice_layer.dart';
import '../practice/practice_state.dart';
import '../data/candle_cache.dart';
import '../data/loaders.dart';
import '../engine/engine_service.dart';
import '../indicators/indicators_state.dart';
import '../run/equity_store.dart';
import '../run/history.dart';
import '../run/protection.dart';
import '../run/run_data.dart';
import '../run/run_view.dart';
import 'app_state.dart';
import 'settings.dart';

class StrategyInfo {
  StrategyInfo(Map j)
      : name = '${j['name']}',
        status = '${j['status']}',
        source = '${j['source'] ?? ''}',
        so = '${j['so'] ?? ''}';
  final String name, status, source, so;
  bool get runnable => status != 'not_built';
}

/// One strategy input, from `hummer inputs` (via the service).
class InputSpec {
  InputSpec(Map j)
      : name = '${j['name']}',
        type = '${j['type']}',
        def = _text(j['default']),
        description = '${j['description'] ?? ''}',
        min = (j['min'] as num?)?.toDouble(),
        max = (j['max'] as num?)?.toDouble(),
        choices = [for (final c in (j['choices'] as List?) ?? const []) '$c'];
  final String name, type, def, description;
  final double? min, max;
  final List<String> choices;

  static String _text(Object? v) => v is double && v == v.truncateToDouble() && v.abs() < 1e15 ? v.toInt().toString() : '$v';

  /// The value's problem in the user's words, or null when it's valid. The engine validates again.
  String? check(String v) {
    switch (type) {
      case 'int':
        final x = int.tryParse(v.trim());
        if (x == null) return 'Whole number';
        if (min != null && x < min!) return 'At least ${_text(min)}';
        if (max != null && x > max!) return 'At most ${_text(max)}';
      case 'double':
        final x = double.tryParse(v.trim());
        if (x == null || !x.isFinite) return 'Number';
        if (min != null && x < min!) return 'At least ${_text(min)}';
        if (max != null && x > max!) return 'At most ${_text(max)}';
      case 'bool':
        if (v != 'true' && v != 'false') return 'true or false';
      case 'timeframe':
        if (!kStrategyTimeframes.contains(v)) return 'One of ${kStrategyTimeframes.join(', ')}';
      case 'choice':
        if (!choices.contains(v)) return 'One of ${choices.join(', ')}';
    }
    return null;
  }
}

const kStrategyTimeframes = ['M1', 'M5', 'M15', 'H1', 'H4', 'D1'];

class BuildState {
  BuildState(this.buildId, this.name, {this.kind = 'strategy'});
  final String buildId, name;

  /// strategy or indicator (SPEC §8.2: build events of indicators carry `kind: "indicator"`).
  final String kind;
  final List<String> lines = [];
  String status = 'running'; // running / ok / failed / stopped
  double? seconds;
  bool get running => status == 'running';
}

class RunProgress {
  RunProgress(this.runId, this.out, this.strategy, this.state);
  final String runId, out, strategy;
  String state; // queued / running / ok / failed / stopped
  String stage = '';
  double pct = 0;
  String simTime = '';
  String? error, signal;
  int? exitCode;
  List<String> journalTail = const [], stderrTail = const [];
  bool get active => state == 'queued' || state == 'running';
}

/// Two runs side by side: report fields from run.json, equity curves from each equity.csv index.
class CompareData {
  CompareData(this.a, this.b);
  final RunManifest a, b;
  EquityStore? ea, eb;
  String? error;
  bool loading = true;
}

/// The tester: engine lifecycle, strategies and builds, inputs and settings, runs, history.
/// All numbers it shows come from engine output; it only reads, filters and lays them out.
class LabState extends ChangeNotifier {
  /// [engine] is for tests (a fake service); the app starts the real one.
  LabState({required this.chart, required this.settings, this.cacheDir, EngineService? engine})
      : engine = engine ?? EngineService(binary: settings.binary, workingDir: settings.engineRepo) {
    this.engine.addListener(notifyListeners);
    _sub = this.engine.events.listen(_onEvent);
    indicators = IndicatorsState(engine: this.engine, chart: chart, settings: settings);
    practice = PracticeState(engine: this.engine, chart: chart, settings: settings, openData: openDataChart, openRunDir: _openRunDir);
    practiceChart = PracticeChart(practice);
    chart.practiceLayer = PracticeLayer(practice, practiceChart);
  }

  /// Practice sessions (M8): manual trading in replay, executed by the engine.
  late final PracticeState practice;
  late final PracticeChart practiceChart;

  /// A finished practice session's folder: listed in History and opened like any run.
  Future<void> _openRunDir(String dir) async {
    await refreshHistory();
    final m = history.where((h) => h.dir == dir).firstOrNull;
    if (m == null) {
      chart.showError('The practice run $dir could not be read.');
      return;
    }
    if (isVisible(m)) await openRun(m);
  }

  final AppState chart;
  final Settings settings;
  final String? cacheDir;
  final EngineService engine;

  /// Navigator → Indicators and the indicators attached to the chart (M7).
  late final IndicatorsState indicators;

  /// The chart's fixed range volume profile tool (drag from candle to candle).
  late final VolumeProfileTool vpTool = VolumeProfileTool(chart: chart, indicators: indicators, build: buildIndicator);

  EngineFreshness? freshness;
  EngineBuild? engineBuild;
  final List<String> engineBuildLines = [];
  bool get engineBuilding => engineBuild != null;
  String? engineBuildResult;

  List<StrategyInfo> strategies = const [];
  final Map<String, List<InputSpec>> schemas = {};
  final Map<String, String> schemaErrors = {};
  BuildState? build;
  RunProgress? progress;

  /// Run events that arrived before start_run's response was handled (same stdout chunk).
  final Map<String, List<Map<String, dynamic>>> _early = {};

  /// The confirmation write in flight; a run's results are opened only after it.
  Future<void>? _confirming;

  List<RunManifest> history = const [];
  bool historyLoading = false;
  final Set<String> compareSel = {};
  CompareData? compare;

  Map<String, dynamic> profile = const {};
  String? profileError;

  /// "Opening run…" while a run's files load.
  String? opening;

  StreamSubscription<Map<String, dynamic>>? _sub;
  Timer? _poll;

  String? get strategy => settings.lastStrategy;
  StrategyInfo? get strategyInfo => strategies.where((s) => s.name == strategy).firstOrNull;
  List<InputSpec>? get schema => strategy == null ? null : schemas[strategy];
  String get runsDir => engine.runsDir.isNotEmpty ? engine.runsDir : settings.runsDir;

  // ── lifecycle ───────────────────────────────────────────────────────
  Future<void> init() async {
    unawaited(loadProfile());
    unawaited(refreshHistory().then((_) => _restoreLastRun()));
    await checkEngine();
    if (!(freshness?.missing ?? true)) await startEngine();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) {
      if (engine.ready && !(build?.running ?? false)) {
        refreshStrategies();
        if (indicators.unsupported == null) indicators.refresh();
      }
    });
  }

  Future<void> checkEngine() async {
    freshness = await checkEngineFreshness(settings.engineRepo, settings.binary);
    notifyListeners();
  }

  Future<void> startEngine() async {
    engine
      ..binary = settings.binary
      ..workingDir = settings.engineRepo;
    await engine.start();
    if (engine.ready) {
      await refreshStrategies();
      await indicators.refresh();
      indicators.syncAll();
      await refreshHistory();
    } else {
      indicators.unsupported = null;
    }
  }

  Future<void> restartEngine() async {
    await engine.shutdown();
    await checkEngine();
    await startEngine();
  }

  /// Builds the engine with its release preset, then restarts the service on success.
  Future<void> buildEngine() async {
    if (engineBuilding) return;
    engineBuildLines.clear();
    engineBuildResult = null;
    chart.showTab(ResultsTab.build);
    try {
      await engine.shutdown();
      engineBuild = await EngineBuild.start(settings.engineRepo, (l) {
        engineBuildLines.add(l);
        notifyListeners();
      });
      notifyListeners();
      final code = await engineBuild!.exitCode;
      engineBuildResult = code == 0 ? 'Engine build OK' : 'Engine build failed (exit code $code)';
    } catch (e) {
      engineBuildResult = "The engine build couldn't be started: $e";
    } finally {
      engineBuild = null;
      notifyListeners();
    }
    await checkEngine();
    await startEngine();
  }

  Future<void> shutdown() async {
    _poll?.cancel();
    engineBuild?.kill();
    await settings.flush();
    await engine.shutdown();
  }

  Future<void> setEnginePaths({String? repo, String? binary}) async {
    if (repo != null) settings.engineRepo = repo.trim();
    if (binary != null) settings.engineBinary = binary.trim();
    settings.changed();
    await restartEngine();
    await loadProfile();
  }

  // ── engine events ───────────────────────────────────────────────────
  void _onEvent(Map<String, dynamic> e) {
    if ('${e['event']}'.startsWith('indicator_') || e['event'] == 'engine_exited') indicators.onEvent(e);
    if ('${e['event']}'.startsWith('session_') || e['event'] == 'engine_exited') practice.onEvent(e);
    final rid = e['run_id'];
    if (rid is String && progress?.runId != rid && '${e['event']}'.startsWith('run_')) {
      if (_early.length > 20) _early.remove(_early.keys.first);
      _early.putIfAbsent(rid, () => []).add(e);
      return;
    }
    switch (e['event']) {
      case 'build_started':
        if (build?.buildId == e['build_id']) build!.status = 'running';
      case 'build_output':
        if (build?.buildId == e['build_id']) build!.lines.add('${e['line']}');
      case 'build_finished':
        final b = build;
        if (b != null && b.buildId == e['build_id']) {
          b.status = '${e['status'] ?? (e['ok'] == true ? 'ok' : 'failed')}';
          b.seconds = (e['seconds'] as num?)?.toDouble();
          if (b.kind == 'indicator') {
            indicators.onBuilt(b.name, b.status == 'ok');
          } else {
            schemas.remove(b.name);
            schemaErrors.remove(b.name);
            refreshStrategies().then((_) {
              if (b.status == 'ok' && b.name == strategy) loadSchema(b.name);
            });
          }
        }
      case 'run_queued':
        if (progress?.runId == e['run_id']) progress!.state = 'queued';
      case 'run_started':
        if (progress?.runId == e['run_id']) progress!.state = 'running';
      case 'run_progress':
        final p = progress;
        if (p != null && p.runId == e['run_id']) {
          p.state = 'running';
          p.pct = (e['pct'] as num?)?.toDouble() ?? p.pct;
          p.simTime = '${e['sim_time'] ?? p.simTime}';
          p.stage = '${e['stage'] ?? (e['pct'] != null ? 'running' : p.stage)}';
        }
      case 'run_finished':
        final p = progress;
        if (p != null && p.runId == e['run_id']) _onRunFinished(p, e);
      case 'engine_exited':
        if (progress?.active ?? false) {
          progress!
            ..state = 'failed'
            ..error = 'The engine stopped during the run.';
        }
        if (build?.running ?? false) build!.status = 'failed';
    }
    notifyListeners();
  }

  Future<void> _onRunFinished(RunProgress p, Map<String, dynamic> e) async {
    await _confirming;
    p.state = '${e['status']}';
    p.error = e['error'] as String?;
    p.signal = e['signal'] as String?;
    p.exitCode = e['exit_code'] as int?;
    p.journalTail = [for (final l in (e['journal_tail'] as List?) ?? const []) '$l'];
    p.stderrTail = [for (final l in (e['stderr_tail'] as List?) ?? const []) '$l'];
    // The finished event carries a summary; it isn't shown here. Results are read from the run's files.
    await refreshHistory();
    if (p.state == 'ok') {
      final m = history.where((h) => h.dir == p.out || h.runId == p.runId).firstOrNull;
      if (m != null) await openRun(m);
    } else if (p.state == 'failed') {
      chart.showError('Run failed: ${_failure(p)}');
    } else if (p.state == 'stopped') {
      chart.showNotice('Run stopped. Its partial output is ignored.');
    }
    notifyListeners();
  }

  String _failure(RunProgress p) {
    final why = p.signal != null ? 'killed by ${p.signal}' : (p.exitCode != null ? 'exit code ${p.exitCode}' : '');
    return [if (p.error != null && p.error!.isNotEmpty) p.error!, if (why.isNotEmpty && !(p.error ?? '').contains(why)) why].join(' · ');
  }

  // ── strategies ──────────────────────────────────────────────────────
  Future<void> refreshStrategies() async {
    if (!engine.ready) return;
    try {
      final r = await engine.request('list_strategies');
      strategies = [for (final s in (r as List)) StrategyInfo(s as Map)];
      if (strategy == null && strategies.isNotEmpty) selectStrategy(strategies.first.name);
      if (strategy != null && schema == null && !schemaErrors.containsKey(strategy) && (strategyInfo?.runnable ?? false)) {
        unawaited(loadSchema(strategy!));
      }
      notifyListeners();
    } catch (_) {
      // engine went away; its status says so
    }
  }

  void selectStrategy(String name) {
    settings.lastStrategy = name;
    settings.changed();
    final info = strategies.where((s) => s.name == name).firstOrNull;
    if (!schemas.containsKey(name) && (info?.runnable ?? false)) loadSchema(name);
    notifyListeners();
  }

  Future<void> loadSchema(String name) async {
    try {
      final r = (await engine.request('strategy_inputs', {'name': name})) as Map;
      schemas[name] = [for (final i in (r['inputs'] as List?) ?? const []) InputSpec(i as Map)];
      schemaErrors.remove(name);
    } on EngineError catch (e) {
      schemaErrors[name] = e.message;
    }
    notifyListeners();
  }

  String inputValue(InputSpec s) => settings.inputs[strategy]?[s.name] ?? s.def;

  void setInput(InputSpec s, String v) {
    final m = settings.inputs.putIfAbsent(strategy!, () => {});
    if (v == s.def) {
      m.remove(s.name);
    } else {
      m[s.name] = v;
    }
    settings.changed();
    notifyListeners();
  }

  void resetInputs() {
    settings.inputs.remove(strategy);
    settings.changed();
    notifyListeners();
  }

  Future<void> buildStrategy() async {
    final name = strategy;
    if (name == null || (build?.running ?? false)) return;
    try {
      final r = (await engine.request('build_strategy', {'name': name})) as Map;
      build = BuildState('${r['build_id']}', name);
      chart.showTab(ResultsTab.build);
    } on EngineError catch (e) {
      chart.showError("Build couldn't start: ${e.message}");
    }
    notifyListeners();
  }

  /// Builds `indicators/<name>.cpp` (same script and flags as strategies); output in the Build tab.
  Future<void> buildIndicator(String name) async {
    if (build?.running ?? false) return;
    try {
      final r = (await engine.request('build_indicator', {'name': name})) as Map;
      build = BuildState('${r['build_id']}', name, kind: 'indicator');
      chart.showTab(ResultsTab.build);
    } on EngineError catch (e) {
      if (isUnknownMethod(e)) {
        indicators.unsupported = IndicatorsState.kUnsupported;
        indicators.refresh();
      } else {
        chart.showError("Build couldn't start: ${e.message}");
      }
    }
    notifyListeners();
  }

  Future<void> stopBuild() async {
    final b = build;
    if (b == null || !b.running) return;
    try {
      await engine.request('stop_build', {'build_id': b.buildId});
    } on EngineError catch (_) {}
  }

  // ── settings ────────────────────────────────────────────────────────
  void set(void Function(Settings s) f) {
    f(settings);
    settings.changed();
    notifyListeners();
  }

  void setCost(String option, String value) {
    final v = value.trim();
    if (v.isEmpty) {
      settings.costs.remove(option);
    } else {
      settings.costs[option] = v;
    }
    settings.changed();
    notifyListeners();
  }

  Future<void> pickDataFile() async {
    final dir = File(settings.dataFile).parent.path;
    final f = await openFile(
      acceptedTypeGroups: [XTypeGroup(label: 'CSV', extensions: const ['csv'])],
      initialDirectory: Directory(dir).existsSync() ? dir : null,
      confirmButtonText: 'Use this data',
    );
    if (f != null) set((s) => s.dataFile = f.path);
  }

  Future<void> loadProfile() async {
    try {
      final j = jsonDecode(await File(settings.profilePath).readAsString());
      profile = (j as Map).cast<String, dynamic>();
      profileError = null;
    } catch (e) {
      profile = const {};
      profileError = "The profile ${settings.profilePath} couldn't be read: $e";
    }
    notifyListeners();
  }

  // ── protected periods ───────────────────────────────────────────────
  ProtectedPeriod? protectionFor(String strategy) => settings.protectionFor(strategy);

  void setProtection(String strategy, ProtectedPeriod? p) {
    settings.protectedPeriods[strategy] = p;
    settings.changed();
    _enforceVisibility();
    notifyListeners();
  }

  /// Whether a run's results may be shown: no protected period for its strategy, no overlap with
  /// its simulated span, or a logged confirmation for that same period in its folder.
  bool isVisible(RunManifest m) {
    final p = protectionFor(m.strategyKey);
    if (p == null) return true;
    final span = m.simSpan;
    if (!p.overlaps(span?.$1, span?.$2)) return true;
    return m.confirmation?.covers(p) ?? false;
  }

  /// The protected period the configured run would touch, or null.
  ProtectedPeriod? protectedOverlap() {
    final s = strategy;
    if (s == null) return null;
    final p = protectionFor(s);
    if (p == null) return null;
    final a = settings.from.isEmpty ? null : dateMs(settings.from);
    final b = settings.to.isEmpty ? null : dateMs(settings.to)! + 86400000 - 1;
    return p.overlaps(a, b) ? p : null;
  }

  /// Logs a reveal of an existing run's results, then lists it normally.
  Future<RunManifest?> revealRun(RunManifest m) async {
    final p = protectionFor(m.strategyKey);
    if (p == null) return m;
    try {
      final c = await writeConfirmation(m.dir, kind: 'reveal', strategy: m.strategyKey, period: p, runFrom: m.from, runTo: m.to);
      final r = m.withConfirmation(c);
      history = [for (final h in history) h.dir == m.dir ? r : h];
      notifyListeners();
      return r;
    } catch (e) {
      chart.showError("The confirmation couldn't be written to ${m.dir}: $e");
      return null;
    }
  }

  void _enforceVisibility() {
    final open = chart.run?.manifest;
    if (open != null && !isVisible(open)) {
      chart.closeRun();
      chart.showNotice('The open run now overlaps a protected period, so it was closed.');
    }
    final c = compare;
    if (c != null && (!isVisible(c.a) || !isVisible(c.b))) compare = null;
    compareSel.removeWhere((d) => history.any((h) => h.dir == d && !isVisible(h)));
  }

  // ── runs ────────────────────────────────────────────────────────────
  /// Problems that stop a run from starting, in the user's words.
  List<String> startProblems() {
    final out = <String>[];
    if (!engine.ready) out.add('The engine is not ready.');
    final info = strategyInfo;
    if (info == null) {
      out.add('Choose a strategy.');
    } else if (!info.runnable) {
      out.add('Build ${info.name} first.');
    }
    if (!File(settings.dataFile).existsSync()) out.add('The data file ${settings.dataFile} does not exist.');
    for (final (k, v) in [('From', settings.from), ('To', settings.to)]) {
      if (v.isNotEmpty && !isIsoDate(v)) out.add('$k must be a date like 2021-01-01.');
    }
    if (isIsoDate(settings.from) && isIsoDate(settings.to) && settings.from.compareTo(settings.to) > 0) out.add('From is after To.');
    for (final (k, v) in [('Deposit', settings.deposit), ('Leverage', settings.leverage)]) {
      if (v.isNotEmpty && (double.tryParse(v) ?? 0) <= 0) out.add('$k must be a positive number.');
    }
    for (final s in schema ?? const <InputSpec>[]) {
      final e = s.check(inputValue(s));
      if (e != null) out.add('${s.name}: $e.');
    }
    return out;
  }

  /// Starts a run. [confirmed] is the protected period the user confirmed in the dialog (if the
  /// run overlaps one); the confirmation is logged in the run's folder with a timestamp.
  Future<void> startRun({ProtectedPeriod? confirmed}) async {
    final problems = startProblems();
    if (problems.isNotEmpty) {
      chart.showError(problems.join(' '));
      return;
    }
    final overlap = protectedOverlap();
    if (overlap != null && confirmed != overlap) {
      chart.showError('This run overlaps the protected period ${overlap.label}; it needs your confirmation.');
      return;
    }
    final s = settings, name = strategy!;
    final inputs = {
      for (final i in schema ?? const <InputSpec>[])
        if (inputValue(i) != i.def) i.name: inputValue(i),
    };
    final options = <String, String>{
      'tick_path': s.tickPath,
      'ambiguity': s.ambiguity,
      if (s.deposit.isNotEmpty) 'deposit': s.deposit,
      if (s.leverage.isNotEmpty) 'leverage': s.leverage,
      ...s.costs,
    };
    try {
      final r = (await engine.request('start_run', {
        'strategy': name,
        'data': s.dataFile,
        'profile': s.profilePath,
        'inputs': inputs,
        if (s.from.isNotEmpty) 'from': s.from,
        if (s.to.isNotEmpty) 'to': s.to,
        'options': options,
        'equity_tf': 'M1',
      })) as Map;
      final p = RunProgress('${r['run_id']}', '${r['out']}', name, '${r['state'] ?? 'running'}');
      progress = p;
      // Logged immediately, before any result is read.
      if (overlap != null) await (_confirming = _logConfirmation(p, overlap));
      _confirming = null;
      for (final ev in _early.remove(p.runId) ?? const <Map<String, dynamic>>[]) {
        _onEvent(ev);
      }
    } on EngineError catch (e) {
      chart.showError("The run couldn't start: ${e.message}");
    }
    notifyListeners();
  }

  Future<void> _logConfirmation(RunProgress p, ProtectedPeriod period) async {
    try {
      await writeConfirmation(p.out, kind: 'start', strategy: p.strategy, period: period, runFrom: settings.from.isEmpty ? null : settings.from, runTo: settings.to.isEmpty ? null : settings.to);
    } catch (e) {
      // Without the log the results would stay hidden, so the run is pointless: stop it.
      await stopRun();
      chart.showError("The protected-period confirmation couldn't be logged in ${p.out} ($e), so the run was stopped.");
    }
  }

  Future<void> stopRun() async {
    final p = progress;
    if (p == null || !p.active) return;
    try {
      await engine.request('stop_run', {'run_id': p.runId});
    } on EngineError catch (e) {
      chart.showError("Couldn't stop the run: ${e.message}");
    }
  }

  Future<void> refreshHistory() async {
    historyLoading = true;
    notifyListeners();
    try {
      history = await scanRuns(runsDir);
    } catch (e) {
      chart.showError("The runs folder $runsDir couldn't be read: $e");
    }
    historyLoading = false;
    _enforceVisibility();
    notifyListeners();
  }

  Future<void> _restoreLastRun() async {
    if (chart.loaded || opening != null) return;
    final d = settings.lastRunDir;
    final m = d == null ? null : history.where((h) => h.dir == d).firstOrNull;
    if (m != null && m.ok && isVisible(m)) {
      await openRun(m);
    } else if (settings.chartDataFile != null && File(settings.chartDataFile!).existsSync()) {
      await openDataChart(settings.chartDataFile);
    }
  }

  /// Shows a data file's candles without a run (default: the Tester's data file), so indicators
  /// can be attached to it. The whole file is shown.
  Future<bool> openDataChart([String? path]) async {
    final p = path ?? settings.dataFile, cache = cacheDir;
    if (!File(p).existsSync()) {
      chart.showError('The data file $p does not exist.');
      return false;
    }
    opening = 'Opening ${baseName(p)}…';
    notifyListeners();
    try {
      final series = await Isolate.run(() => runSeries(p, cache, null));
      await chart.showData(series, p);
      settings
        ..chartDataFile = p
        ..lastRunDir = null;
      settings.changed();
      return true;
    } on LoadError catch (e) {
      chart.showError('Candles: ${e.message}');
    } catch (e) {
      chart.showError("The data file couldn't be opened: $e");
    } finally {
      opening = null;
      notifyListeners();
    }
    return false;
  }

  /// Opens a finished run: its files, its equity index and the candles of its data file,
  /// cut at the run's last simulated bar. Never for a run whose results are protected.
  Future<bool> openRun(RunManifest m) async {
    if (!isVisible(m)) {
      chart.showError('${m.runId} overlaps the protected period ${protectionFor(m.strategyKey)?.label}. Confirm it from Run history to see it.');
      return false;
    }
    if (!m.ok) {
      chart.showError('${m.runId} did not finish (${m.result}).');
      return false;
    }
    opening = 'Opening ${m.runId}…';
    notifyListeners();
    try {
      final dir = m.dir, path = m.dataPath, cache = cacheDir;
      final dataF = Isolate.run(() => loadRunFiles(dir));
      final eqF = EquityStore.open(joinPath(dir, 'equity.csv')).then<Object>((e) => e, onError: (Object e) => '$e');
      final last = m.lastSimMs;
      final seriesF = Isolate.run(() => runSeries(path, cache, last));
      final data = await dataF;
      final series = await seriesF;
      final eq = await eqF;
      final view = RunView(data, eq is EquityStore ? eq : null, equityError: eq is String ? eq : null);
      final tf = data.manifest.inputsEffective['Tf'];
      await chart.showRun(view, series, path, tf: tf);
      final notes = <String>[
        if (eq is String) "equity.csv couldn't be read ($eq), so the graph and the readouts are empty.",
        if (m.equityTf != 'M1') 'This run kept equity per ${m.equityTf}, so replay readouts update once per ${m.equityTf} bar.',
        if ((m.json['data'] as Map?)?['bytes'] != null && File(path).lengthSync() != (m.json['data'] as Map)['bytes'])
          'The data file has changed since this run; the candles may not match its trades.',
      ];
      if (notes.isNotEmpty) chart.showNotice(notes.join(' '));
      settings
        ..lastRunDir = m.dir
        ..chartDataFile = null;
      settings.changed();
      return true;
    } on RunLoadError catch (e) {
      chart.showError(e.message);
    } on LoadError catch (e) {
      chart.showError('Candles: ${e.message}');
    } catch (e) {
      chart.showError("The run couldn't be opened: $e");
    } finally {
      opening = null;
      notifyListeners();
    }
    return false;
  }

  // ── compare ─────────────────────────────────────────────────────────
  void toggleCompare(RunManifest m) {
    if (!compareSel.remove(m.dir)) {
      if (compareSel.length >= 2) compareSel.remove(compareSel.first);
      compareSel.add(m.dir);
    }
    notifyListeners();
  }

  Future<void> openCompare() async {
    final sel = [for (final d in compareSel) history.where((h) => h.dir == d).firstOrNull].whereType<RunManifest>().toList();
    if (sel.length != 2 || !sel.every(isVisible)) return;
    final c = CompareData(sel[0], sel[1]);
    compare = c;
    notifyListeners();
    try {
      final r = await Future.wait([
        Isolate.run(() => scanEquityFile(joinPath(c.a.dir, 'equity.csv'), targetBuckets: 1500)),
        Isolate.run(() => scanEquityFile(joinPath(c.b.dir, 'equity.csv'), targetBuckets: 1500)),
      ]);
      c.ea = EquityStore(joinPath(c.a.dir, 'equity.csv'), r[0]);
      c.eb = EquityStore(joinPath(c.b.dir, 'equity.csv'), r[1]);
    } catch (e) {
      c.error = "Equity curves couldn't be read: $e";
    }
    c.loading = false;
    notifyListeners();
  }

  void closeCompare() {
    compare?.ea?.close();
    compare?.eb?.close();
    compare = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _sub?.cancel();
    indicators.dispose();
    practiceChart.dispose();
    practice.dispose();
    engine.removeListener(notifyListeners);
    engine.dispose();
    super.dispose();
  }
}
