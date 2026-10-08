import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';

import '../data/baseline.dart';
import '../data/bookmarks.dart';
import '../data/candles.dart';
import '../data/conditions_summary.dart';
import '../data/events.dart';
import '../data/loaders.dart';
import '../data/predictions.dart';
import '../data/prefs.dart';
import '../data/resample.dart';
import '../data/sample_data.dart';
import '../data/stats.dart';
import '../demo/demo_events.dart';
import '../util/format.dart';

enum Mode { explore, replay }

class HoverInfo {
  const HoverInfo(this.bar, this.y);
  final int bar;
  final double y;
}

class Drill {
  const Drill({required this.ev, required this.zone, required this.prevTf, required this.prevViewStart, required this.prevZoom});
  final FvgEvent ev;
  final Zone zone;
  final String prevTf;
  final int prevViewStart, prevZoom;
}

const kFilterOptions = <String, List<String>>{
  'Scenario': ['All', 'Bounced inside gap', 'Wick through then bounced', 'Closed beyond then reclaimed', 'Broke through', 'No resolution'],
  'Direction': ['Both', 'Bullish', 'Bearish'],
  'Gap size': ['All', 'Q1 small', 'Q2', 'Q3', 'Q4 big'],
  'Displacement': ['All', ...kDispBuckets],
  'Formation session': ['All', ...kSessions],
  'Touch session': ['All', ...kSessions],
  'HTF trend': ['All', 'Aligned', 'Against'],
  'Age': ['All', ...kAgeBuckets],
  'Sweep': ['All', 'Yes', 'No'],
  'Period': ['All', 'In-sample 2021–23', 'Out-of-sample 2024–25', 'Hold-out 2026'],
};

/// Filter column each optional filter needs in fvg_events.csv.
const _filterColumn = {'Displacement': 'disp_q', 'HTF trend': 'htf_trend', 'Sweep': 'sweep'};

/// Saved filter presets (unlisted keys reset to All).
const kFilterPresets = <String, Map<String, int>>{
  'Asia formation (candidate)': {'Formation session': 1},
};
const kPeriodHoldout = 3;
const kSpeeds = [1, 2, 5, 10, 25, 50, 100];

final _csv = XTypeGroup(label: 'CSV', extensions: const ['csv']);

// Top-level so the isolate closures capture only their arguments.
Future<Candles> _parseCandlesIso(String path) => Isolate.run(() => parseCandlesFile(path));
Future<EventsParse> _parseEventsIso(String path, bool companion) => Isolate.run(() => parseEventsFile(path, companion: companion));
Future<Candles> _resampleIso(Candles src, int minutes) => Isolate.run(() => resample(src, minutes));

class AppState extends ChangeNotifier {
  // ── data ────────────────────────────────────────────────────────────
  final Map<String, Candles> series = {}; // per timeframe cache
  String? baseTf;
  String timeframe = 'M15';
  String? candlesPath, eventsPath, lastDir;
  bool isSample = false;

  List<FvgEvent> events = const [];
  final Map<String, FvgEvent> _byId = {};
  String? eventsTf;
  int unmatchedEvents = 0;
  Baseline? baseline;
  BookmarkStore bookmarks = BookmarkStore(null);

  List<FvgEvent> filtered = const [];
  StudyStats stats = StudyStats.empty;

  /// Companion outputs from the study, matched by the same filters.
  List<FvgEvent> fakeEvents = const [], controlEvents = const [];

  /// [controlEvents] split by kind once at load.
  List<FvgEvent> get _controlReal => _ctrlSplit.$1;
  List<FvgEvent> get _controlFake => _ctrlSplit.$2;
  (List<FvgEvent>, List<FvgEvent>) _ctrlSplit = (const [], const []);
  List<FvgEvent>? _ctrlSplitOf;
  Set<String> eventColumns = const {};
  Comparison comparison = const Comparison(RateSummary(0, 0, 0), null, null, null);
  List<double?>? fakeCurve;

  /// Hold-out (2026) stats stay hidden until revealed; the reveal date is recorded.
  DateTime? holdoutRevealedAt;
  int holdoutExcluded = 0;
  bool get holdoutLocked => holdoutRevealedAt == null;
  bool get statsLocked => holdoutLocked && filters['Period'] == kPeriodHoldout;
  List<Zone> zones = const [];
  final Map<int, List<Zone>> _touchAt = {};
  final Set<int> _endAt = {};
  final Map<String, Zone> _zoneById = {};

  /// Display only — the study itself runs in Python.
  double k = 1.0, failBuffer = 0.25;

  // ── ui ──────────────────────────────────────────────────────────────
  String? busy, error, notice;
  Mode mode = Mode.explore;
  bool leftOpen = false, rightOpen = false, bottomOpen = false, focus = false, starredOnly = false;
  bool selectMode = false, jumpOpen = false, playing = false, predict = false;
  int zoom = 150, viewStart = 0, cursor = 0, replayStart = 0, speed = 2;

  /// While awaiting a prediction: the hidden first-touch bar (only its open is drawn).
  int? peek;
  String? pending, selected;
  Drill? drill;
  int pulseFrom = -1, pulseTo = -1;

  /// Session-wide predictions (survive replay restarts).
  final Map<String, String> calls = {};
  final List<PredictionRecord> predictionLog = [];

  final Map<String, int> filters = {for (final k in kFilterOptions.keys) k: 0};
  String search = '';

  final hover = ValueNotifier<HoverInfo?>(null);
  final pulseTick = ValueNotifier<int>(0);
  Timer? _timer;
  final Stopwatch _sw = Stopwatch();
  int _done = 0;
  bool _resumeAfterGuess = false;

  Candles? get candles => series[timeframe];
  int get n => candles?.length ?? 0;
  bool get loaded => n > 0;
  bool get eventsLoaded => events.isNotEmpty;
  bool get isReplay => mode == Mode.replay;
  bool get hasM1 => series.containsKey('M1');
  bool get zonesOnChart => drill != null || (eventsTf != null && timeframe == eventsTf);

  /// The only "now". Nothing right of it may be drawn or read.
  int get visibleCursor => isReplay && !selectMode ? cursor : n - 1;

  FvgEvent? get selectedEvent => selected == null ? null : _byId[selected];
  FvgEvent? eventById(String? id) => id == null ? null : _byId[id];
  Zone? zoneFor(String id) => _zoneById[id];
  DateTime timeOf(int i) {
    final c = candles;
    if (c == null || c.length == 0) return DateTime.utc(2000);
    if (i < c.length) return c.time(max(0, i));
    return c.time(c.length - 1).add(Duration(minutes: c.minutes * (i - c.length + 1)));
  }

  int clampV(int v) => v.clamp(0, max(0, n - zoom)).toInt();
  bool tfAvailable(String tf) {
    final b = baseTf;
    if (b == null || isReplay || drill != null) return false;
    final m = tfMinutes(tf), bm = tfMinutes(b);
    return m >= bm && m % bm == 0;
  }

  // ── loading ─────────────────────────────────────────────────────────
  Future<T?> _busy<T>(String label, Future<T> Function() f) async {
    busy = label;
    error = null;
    notifyListeners();
    try {
      return await f();
    } on LoadError catch (e) {
      error = e.message;
      return null;
    } catch (e) {
      error = 'Something went wrong while reading the file: $e';
      return null;
    } finally {
      busy = null;
      notifyListeners();
    }
  }

  /// Restores the last folder used in a file dialog (path_provider).
  Future<void> restorePrefs() async {
    lastDir ??= await Prefs.lastDir();
  }

  void _rememberDir(String filePath) {
    lastDir = File(filePath).parent.path;
    Prefs.setLastDir(lastDir!);
  }

  Future<void> pickCandles() async {
    final f = await openFile(acceptedTypeGroups: [_csv], initialDirectory: lastDir, confirmButtonText: 'Load candles');
    if (f != null) await loadCandles(f.path);
  }

  Future<void> pickEvents() async {
    final f = await openFile(acceptedTypeGroups: [_csv], initialDirectory: lastDir, confirmButtonText: 'Load events');
    if (f != null) await loadEvents(f.path);
  }

  Future<void> reload() async {
    final cp = candlesPath, ep = eventsPath;
    if (cp != null) await loadCandles(cp);
    if (ep != null) await loadEvents(ep);
  }

  void _clearSample() {
    if (!isSample) return;
    isSample = false;
    series.clear();
    baseTf = null;
    events = const [];
    _byId.clear();
    baseline = null;
    eventsPath = null;
    fakeEvents = const [];
    controlEvents = const [];
    eventColumns = const {};
    holdoutRevealedAt = null;
    calls.clear();
    predictionLog.clear();
  }

  Future<void> loadCandles(String path) async {
    _rememberDir(path);
    final c = await _busy('Loading candles…', () => _parseCandlesIso(path));
    if (c == null) return;
    _clearSample();
    _exitReplayQuiet();
    drill = null;
    series
      ..clear()
      ..[c.tf] = c;
    baseTf = c.tf;
    timeframe = c.tf;
    candlesPath = path;
    _resetView();
    await _mapAndApply();
  }

  Future<void> loadEvents(String path) async {
    _rememberDir(path);
    final notes = <String>[];
    // fvg_events_app.csv is fvg_events.csv plus the condition columns; prefer it when it sits alongside.
    if (path.split(RegExp(r'[\\/]')).last == 'fvg_events.csv') {
      final app = siblingPath(path, 'fvg_events_app.csv');
      if (await File(app).exists()) {
        path = app;
        notes.add('Loaded fvg_events_app.csv from the same folder (fvg_events.csv plus the condition columns).');
      }
    }
    final r = await _busy('Loading events…', () => _parseEventsIso(path, false));
    if (r == null) return;
    _clearSample();
    events = r.events;
    eventColumns = r.columns;
    _byId
      ..clear()
      ..addEntries(events.map((e) => MapEntry(e.id, e)));
    eventsPath = path;
    selected = null;
    if (r.skipped > 0) notes.add("${fmtInt(r.skipped)} rows in fvg_events.csv couldn't be read and were skipped.");
    try {
      // Only a fallback for the faint fake-zone curve when fvg_fake_events.csv is missing.
      baseline = await loadBaselineNextTo(path);
    } catch (e) {
      baseline = null;
      notes.add("fvg_baseline_summary.json couldn't be read ($e).");
    }
    bookmarks = await BookmarkStore.load(siblingPath(path, 'fvg_bookmarks.json'));
    fakeEvents = await _loadCompanion(path, 'fvg_fake_events.csv', notes);
    controlEvents = await _loadCompanion(path, 'fvg_control_events.csv', notes);
    if (controlEvents.any((e) => e.kind != 'real' && e.kind != 'fake')) {
      notes.add('fvg_control_events.csv needs a kind column (real / fake). Re-run fvg_conditions.py.');
      controlEvents = const [];
    }
    holdoutRevealedAt = await _readHoldout(path);
    final missingCols = _filterColumn.entries.where((e) => !eventColumns.contains(e.value)).map((e) => e.key).toList();
    if (missingCols.isNotEmpty) notes.add('No ${missingCols.join(', ')} column in fvg_events.csv, so those filters are off.');
    await _mapAndApply(notes);
    _crossCheckSummary(path);
  }

  Future<List<FvgEvent>> _loadCompanion(String eventsPath, String name, List<String> notes) async {
    final p = siblingPath(eventsPath, name);
    if (!await File(p).exists()) {
      notes.add('No $name next to the events file.');
      return const [];
    }
    try {
      final r = await _parseEventsIso(p, true);
      return r.events;
    } on LoadError catch (e) {
      notes.add(e.message);
    } catch (e) {
      notes.add("$name couldn't be read ($e).");
    }
    return const [];
  }

  /// The comparison card is built from the per-event files; fvg_conditions_summary.json
  /// is the study's own table, so any disagreement means the files come from different runs.
  /// Runs in the background (it takes a couple of seconds) and only speaks up on a mismatch.
  void _crossCheckSummary(String path) {
    Isolate.run(() => crossCheckFiles(path)).then((bad) {
      if (bad == null || bad.isEmpty || eventsPath != path) return;
      notice = [
        ?notice,
        "${bad.length} buckets don't match fvg_conditions_summary.json (e.g. ${bad.first}). "
            'The files may come from different runs. Re-run fvg_conditions.py and reload.',
      ].join(' ');
      notifyListeners();
    }, onError: (Object e) {
      if (eventsPath != path) return;
      notice = "fvg_conditions_summary.json couldn't be checked ($e).";
      notifyListeners();
    });
  }

  Future<DateTime?> _readHoldout(String eventsPath) async {
    final f = File(siblingPath(eventsPath, 'fvg_holdout.json'));
    if (!await f.exists()) return null;
    try {
      final j = jsonDecode(await f.readAsString());
      return j is Map ? DateTime.tryParse('${j['revealed_at']}') : null;
    } catch (_) {
      return null;
    }
  }

  /// Unlocks hold-out stats and records when it happened (fvg_holdout.json next to the events file).
  Future<void> revealHoldout() async {
    if (!holdoutLocked) return;
    holdoutRevealedAt = DateTime.now().toUtc();
    final ep = eventsPath;
    if (ep != null) {
      try {
        await File(siblingPath(ep, 'fvg_holdout.json')).writeAsString(const JsonEncoder.withIndent('  ').convert({
          'revealed_at': holdoutRevealedAt!.toIso8601String(),
          'events_file': ep.split(RegExp(r'[\\/]')).last,
          'filters_at_reveal': {for (final e in filters.entries) if (e.value != 0) e.key: kFilterOptions[e.key]![e.value]},
        }));
      } catch (e) {
        error = "Hold-out revealed, but the record couldn't be saved: $e";
      }
    }
    notice = 'Hold-out revealed ${fmtFull(holdoutRevealedAt!)} UTC. Recorded in fvg_holdout.json.';
    _applyFilters();
    notifyListeners();
  }

  /// Explore view hides hold-out outcomes while locked. Replay still reveals them bar by bar.
  bool outcomeHidden(FvgEvent e) => holdoutLocked && e.isHoldout && !(isReplay && !selectMode);

  bool filterAvailable(String key) {
    final c = _filterColumn[key];
    return c == null || eventColumns.contains(c);
  }

  void applyFilterPreset(String name) {
    final p = kFilterPresets[name];
    if (p == null) return;
    for (final k in filters.keys) {
      filters[k] = p[k] ?? 0;
    }
    _applyFilters();
    notifyListeners();
  }

  void clearFilters() {
    for (final k in filters.keys) {
      filters[k] = 0;
    }
    starredOnly = false;
    _applyFilters();
    notifyListeners();
  }

  bool get anyFilter => starredOnly || filters.values.any((v) => v != 0);

  Future<void> _mapAndApply([List<String>? notes]) async {
    notes ??= [];
    eventsTf = null;
    unmatchedEvents = 0;
    if (events.isNotEmpty && baseTf != null) {
      final b = baseTf!;
      final candidates = tfMinutes(b) == 1 ? ['M15', 'M5', 'H1', 'M1'] : [b];
      for (final tf in candidates) {
        final c = await _ensureTf(tf);
        if (c == null) continue;
        final miss = mapEvents(events, c);
        if (miss < events.length / 2) {
          eventsTf = tf;
          unmatchedEvents = miss;
          break;
        }
      }
      if (eventsTf == null) {
        for (final e in events) {
          e.formedIdx = e.touchIdx = e.endIdx = -1;
        }
        unmatchedEvents = events.length;
        error = "None of the event times match the candle file. Times must match exactly (e.g. 2021-01-03 23:00:00), "
            'so check both files come from the same download.';
      } else {
        if (unmatchedEvents > 0) {
          notes.insert(0, "${fmtInt(unmatchedEvents)} events have times that aren't in the candle file. They count in the stats but aren't drawn.");
        }
        if (timeframe != eventsTf && drill == null && !isReplay) {
          timeframe = eventsTf!;
          _resetView();
        }
      }
    }
    notice = notes.isEmpty ? null : notes.join(' ');
    _applyFilters();
    notifyListeners();
  }

  Future<Candles?> _ensureTf(String tf) async {
    final have = series[tf];
    if (have != null) return have;
    final b = baseTf == null ? null : series[baseTf!];
    if (b == null) return null;
    final m = tfMinutes(tf);
    if (m < b.minutes || m % b.minutes != 0) return null;
    final prev = busy;
    busy = 'Resampling to $tf…';
    notifyListeners();
    try {
      final r = await _resampleIso(b, m);
      series[tf] = r;
      return r;
    } finally {
      busy = prev;
      notifyListeners();
    }
  }

  Future<void> setTimeframe(String tf) async {
    if (tf == timeframe || !tfAvailable(tf) || !loaded) return;
    final centerMs = candles!.t[(viewStart + zoom ~/ 2).clamp(0, n - 1).toInt()];
    final c = await _ensureTf(tf);
    if (c == null) return;
    timeframe = tf;
    zoom = min(zoom, max(40, n));
    viewStart = clampV(c.lowerBound(centerMs) - zoom ~/ 2);
    cursor = n - 1;
    _rebuildZones();
    notifyListeners();
  }

  void _resetView() {
    zoom = min(150, max(40, n));
    viewStart = clampV(n - zoom);
    cursor = max(0, n - 1);
  }

  void clearMessage() {
    error = null;
    notice = null;
    notifyListeners();
  }

  // ── filters / stats / zones ─────────────────────────────────────────
  /// The active filters as one test, resolved once per change (it runs over ~170k events).
  bool Function(FvgEvent) _filterTest() {
    int f(String k) => filters[k]!;
    final sc = f('Scenario'), dir = f('Direction'), sz = f('Gap size'), disp = f('Displacement');
    final fs = f('Formation session'), tsn = f('Touch session'), tr = f('HTF trend'), age = f('Age');
    final sw = f('Sweep'), per = f('Period');
    final scenario = sc > 0 ? kScenarioCodes[sc - 1] : null, size = sz > 0 ? kFilterOptions['Gap size']![sz] : null;
    final dispQ = disp > 0 ? kDispBuckets[disp - 1] : null, ageB = age > 0 ? kAgeBuckets[age - 1] : null;
    final form = fs > 0 ? kSessions[fs - 1] : null, touch = tsn > 0 ? kSessions[tsn - 1] : null;
    final trend = tr > 0 ? (tr == 1 ? 'Aligned' : 'Against') : null;
    return (e) {
      if (scenario != null && e.scenario != scenario) return false;
      if (dir > 0 && e.isBull != (dir == 1)) return false;
      if (size != null && e.sizeQ != size) return false;
      if (dispQ != null && e.dispQ != dispQ) return false;
      if (form != null && e.session != form) return false;
      if (touch != null && e.touchSession != touch) return false;
      if (trend != null && e.htfTrend != trend) return false;
      if (ageB != null && e.ageBucket != ageB) return false;
      if (sw > 0 && e.sweep != (sw == 1)) return false;
      if (per > 0 && e.period.index != per - 1) return false;
      return true;
    };
  }

  void _applyFilters() {
    if (!identical(_ctrlSplitOf, controlEvents)) {
      _ctrlSplitOf = controlEvents;
      _ctrlSplit = (controlEvents.where((e) => e.kind == 'real').toList(), controlEvents.where((e) => e.kind == 'fake').toList());
    }
    final match = _filterTest(), starred = starredOnly;
    filtered = events.where((e) => match(e) && (!starred || bookmarks.starred(e.id))).toList();
    final locked = holdoutLocked;
    bool open(FvgEvent e) => !(locked && e.isHoldout);
    holdoutExcluded = locked ? filtered.where((e) => e.isHoldout).length : 0;
    final real = filtered.where(open).toList();
    stats = computeStats(real);
    final fake = fakeEvents.where((e) => match(e) && open(e)).toList();
    final hasCtrl = controlEvents.isNotEmpty;
    fakeCurve = fakeEvents.isEmpty ? null : depthCurve(fake).curve;
    comparison = Comparison(
      rateOf(real),
      fakeEvents.isEmpty ? null : rateOf(fake),
      hasCtrl ? rateOf(_controlReal.where((e) => match(e) && open(e))) : null,
      hasCtrl ? rateOf(_controlFake.where((e) => match(e) && open(e))) : null,
    );
    _rebuildZones();
  }

  void _rebuildZones() {
    _touchAt.clear();
    _endAt.clear();
    _zoneById.clear();
    final out = <Zone>[];
    final d = drill;
    if (d != null) {
      out.add(d.zone);
    } else if (zonesOnChart) {
      for (final e in filtered) {
        if (e.mapped) out.add(Zone(e, max(0, e.formedIdx - 2), e.formedIdx, e.touchIdx, e.endIdx));
      }
    }
    zones = out;
    for (final z in out) {
      _touchAt.putIfAbsent(z.touch, () => []).add(z);
      _endAt.add(z.end);
      _zoneById[z.ev.id] = z;
    }
  }

  void setFilter(String key, int i) {
    filters[key] = i;
    _applyFilters();
    notifyListeners();
  }

  void toggleStarredOnly() {
    starredOnly = !starredOnly;
    _applyFilters();
    notifyListeners();
  }

  // ── bookmarks ───────────────────────────────────────────────────────
  void toggleStar(String id) {
    bookmarks.toggleStar(id);
    if (starredOnly) _applyFilters();
    notifyListeners();
  }

  void setNote(String id, String text) {
    bookmarks.setNote(id, text);
    notifyListeners();
  }

  // ── chrome ──────────────────────────────────────────────────────────
  void toggleLeft([bool? v]) => _set(() => leftOpen = v ?? !leftOpen);
  void toggleRight() => _set(() => rightOpen = !rightOpen);
  void toggleBottom() {
    if (loaded || eventsLoaded) _set(() => bottomOpen = !bottomOpen);
  }

  void toggleFocus() => _set(() => focus = !focus);
  void toggleLayer(String id) => _set(() => layersOn.contains(id) ? layersOn.remove(id) : layersOn.add(id));
  final Set<String> layersOn = {'fvg', 'levels', 'labels'};
  void setSearch(String q) => _set(() => search = q);
  void setK(double v) => _set(() => k = v.clamp(0.25, 3.0).toDouble());
  void setFailBuffer(double v) => _set(() => failBuffer = v.clamp(0.0, 1.0).toDouble());

  void escape() {
    if (drill != null) {
      exitDrill();
      return;
    }
    _set(() {
      selectMode = false;
      jumpOpen = false;
      leftOpen = false;
    });
  }

  // ── view ────────────────────────────────────────────────────────────
  void zoomBy(double f) => _set(() {
        final end = viewStart + zoom;
        zoom = (zoom * f).round().clamp(40, max(40, n)).toInt();
        viewStart = clampV(end - zoom);
      });
  void fit() => _set(() {
        zoom = max(40, n);
        viewStart = 0;
      });
  void pan(int d) => _set(() => viewStart = clampV(viewStart + d));

  void select(String? id, {bool reveal = false}) => _set(() {
        selected = id;
        final z = id == null ? null : _zoneById[id];
        if (reveal && z != null && !isReplay && drill == null) viewStart = clampV(z.formed - (zoom * 0.45).floor());
      });

  // ── M1 drill-down ───────────────────────────────────────────────────
  void viewOnM1() {
    final ev = selectedEvent, m1 = series['M1'];
    if (ev == null || m1 == null || isReplay || drill != null) return;
    final em = tfMinutes(eventsTf ?? 'M15') * 60000;
    final start = m1.lowerBound(ev.formationMs - 2 * em);
    final formed = max(start, m1.lowerBound(ev.formationMs + em) - 1);
    final tFrom = m1.lowerBound(ev.touchMs), tTo = m1.lowerBound(ev.touchMs + em) - 1;
    var touch = tFrom;
    for (var i = tFrom; i <= tTo && i < m1.length; i++) {
      if (ev.isBull ? m1.l[i] <= ev.edge : m1.h[i] >= ev.edge) {
        touch = i;
        break;
      }
    }
    final end = max(touch, m1.lowerBound(ev.endMs + em) - 1);
    drill = Drill(ev: ev, zone: Zone(ev, start, formed, touch, end), prevTf: timeframe, prevViewStart: viewStart, prevZoom: zoom);
    timeframe = 'M1';
    zoom = (end - start + 60).clamp(40, max(40, m1.length)).toInt();
    viewStart = clampV(start - 20);
    cursor = n - 1;
    hover.value = null;
    _rebuildZones();
    notifyListeners();
  }

  void exitDrill() {
    final d = drill;
    if (d == null) return;
    drill = null;
    timeframe = d.prevTf;
    zoom = d.prevZoom;
    viewStart = clampV(d.prevViewStart);
    cursor = n - 1;
    hover.value = null;
    _rebuildZones();
    notifyListeners();
  }

  // ── replay ──────────────────────────────────────────────────────────
  void setMode(Mode m) => m == Mode.replay ? enterReplay() : exitReplay();

  void enterReplay() {
    if (isReplay || !loaded) return;
    if (drill != null) exitDrill();
    mode = Mode.replay;
    selectMode = true;
    playing = false;
    peek = null;
    pending = null;
    cursor = n - 1;
    hover.value = null;
    _syncTimer();
    notifyListeners();
  }

  void _exitReplayQuiet() {
    mode = Mode.explore;
    selectMode = false;
    playing = false;
    peek = null;
    pending = null;
    jumpOpen = false;
    _syncTimer();
  }

  void exitReplay() {
    _exitReplayQuiet();
    cursor = n - 1;
    viewStart = clampV(n - zoom);
    notifyListeners();
  }

  void startAt(int bar) {
    cursor = bar.clamp(0, max(0, n - 1)).toInt();
    replayStart = cursor;
    selectMode = false;
    playing = false;
    peek = null;
    pending = null;
    jumpOpen = false;
    viewStart = clampV(cursor - (zoom * 0.7).floor());
    _syncTimer();
    notifyListeners();
  }

  void toggleSelect() {
    selectMode = !selectMode;
    playing = false;
    jumpOpen = false;
    peek = null;
    pending = null;
    _syncTimer();
    notifyListeners();
  }

  void toggleJump() => _set(() {
        jumpOpen = !jumpOpen;
        selectMode = false;
      });

  void jumpTo(DateTime t) {
    final c = candles;
    if (c != null) startAt(c.lowerBound(t.millisecondsSinceEpoch));
  }

  /// Starts replay 50 bars before the selected gap forms.
  void replaySelected() {
    final z = selected == null ? null : _zoneById[selected];
    if (z == null) return;
    if (drill != null) exitDrill();
    mode = Mode.replay;
    startAt(max(0, z.formed - 50));
  }

  void togglePlay() {
    if (!isReplay || peek != null || selectMode) return;
    if (!playing && cursor >= n - 1) return;
    playing = !playing;
    _syncTimer();
    notifyListeners();
  }

  void setSpeed(int v) {
    speed = v;
    _syncTimer();
    notifyListeners();
  }

  void togglePredict() => _set(() {
        predict = !predict;
        if (!predict) {
          peek = null;
          pending = null;
        }
      });

  void toStart() {
    cursor = replayStart;
    peek = null;
    pending = null;
    playing = false;
    viewStart = clampV(cursor - (zoom * 0.7).floor());
    _syncTimer();
    notifyListeners();
  }

  Zone? _unpredictedTouch(int bar) {
    final l = _touchAt[bar];
    if (l == null) return null;
    for (final z in l) {
      if (!calls.containsKey(z.ev.id)) return z;
    }
    return null;
  }

  /// Pause *before* revealing the touch bar: cursor stays on the previous bar,
  /// only the touch bar's open is drawn.
  void _pauseOnTouch(int bar, Zone z) {
    peek = bar;
    pending = z.ev.id;
    _resumeAfterGuess = _resumeAfterGuess || playing;
    playing = false;
    _syncTimer();
  }

  void _advance(int steps) {
    if (!isReplay || selectMode || peek != null || !loaded) return;
    final from = cursor;
    for (var i = 0; i < steps; i++) {
      final next = cursor + 1;
      if (next > n - 1) {
        playing = false;
        _syncTimer();
        break;
      }
      if (predict) {
        final z = _unpredictedTouch(next);
        if (z != null) {
          _pauseOnTouch(next, z);
          break;
        }
      }
      cursor = next;
    }
    _afterMove(from);
  }

  void _afterMove(int from) {
    viewStart = _follow(peek ?? cursor);
    if (cursor > from) {
      var hit = false;
      for (var i = from + 1; i <= cursor && !hit; i++) {
        if (_endAt.contains(i)) hit = true;
      }
      if (hit) {
        pulseFrom = from;
        pulseTo = cursor;
        pulseTick.value++;
      }
    }
    notifyListeners();
  }

  void step(int d) {
    if (!isReplay || selectMode || !loaded) return;
    if (d > 0) {
      _resumeAfterGuess = false;
      _advance(d);
      return;
    }
    if (peek != null) {
      peek = null;
      pending = null;
      notifyListeners();
      return;
    }
    cursor = max(0, cursor + d);
    viewStart = _follow(cursor);
    notifyListeners();
  }

  void guess(String call) {
    final id = pending, bar = peek;
    if (id == null || bar == null) return;
    final ev = _byId[id];
    if (ev != null) {
      calls[id] = call;
      predictionLog.add(PredictionRecord.of(ev, call, DateTime.now().toUtc()));
    }
    final another = _unpredictedTouch(bar);
    if (another != null) {
      pending = another.ev.id;
      notifyListeners();
      return;
    }
    final from = cursor;
    cursor = bar;
    peek = null;
    pending = null;
    playing = _resumeAfterGuess && cursor < n - 1;
    _resumeAfterGuess = false;
    _syncTimer();
    _afterMove(from);
  }

  /// N: put the cursor on the bar just before the next first touch.
  void nextTouch() {
    if (!isReplay || selectMode || peek != null || !loaded) return;
    int? best;
    for (final z in zones) {
      if (z.touch > cursor + 1 && (best == null || z.touch < best)) best = z.touch;
    }
    if (best == null) return;
    final from = cursor;
    cursor = best - 1;
    if (predict) {
      final z = _unpredictedTouch(best);
      if (z != null) _pauseOnTouch(best, z);
    }
    _afterMove(from);
  }

  /// Shift+→: next formation, first touch or resolution.
  void nextEvent() {
    if (!isReplay || selectMode || peek != null || !loaded) return;
    int? best;
    for (final z in zones) {
      for (final b in [z.formed, z.touch, z.end]) {
        if (b > cursor && (best == null || b < best)) best = b;
      }
    }
    if (best == null) return;
    final from = cursor;
    final z = predict ? _unpredictedTouch(best) : null;
    if (z != null) {
      cursor = best - 1;
      _pauseOnTouch(best, z);
    } else {
      cursor = best;
    }
    _afterMove(from);
  }

  int _follow(int c) {
    final lim = viewStart + (zoom * 0.85).floor();
    if (c > lim) return clampV(c - (zoom * 0.85).floor());
    if (c < viewStart + 4) return clampV(c - (zoom * 0.5).floor());
    return viewStart;
  }

  /// 60 Hz tick; advances however many bars are due so the UI repaints at most
  /// ~60 times per second even at 100 bars/s.
  void _syncTimer() {
    _timer?.cancel();
    _timer = null;
    if (!playing) return;
    _sw
      ..reset()
      ..start();
    _done = 0;
    _timer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      final due = _sw.elapsedMilliseconds * speed ~/ 1000;
      final k = due - _done;
      if (k <= 0) return;
      _done = due;
      _advance(k);
    });
  }

  // ── predictions ─────────────────────────────────────────────────────
  Future<void> exportPredictions() async {
    if (predictionLog.isEmpty) return;
    final now = DateTime.now();
    String p2(int v) => v.toString().padLeft(2, '0');
    final loc = await getSaveLocation(
      acceptedTypeGroups: [_csv],
      initialDirectory: lastDir,
      suggestedName: 'fvg_predictions_${now.year}${p2(now.month)}${p2(now.day)}_${p2(now.hour)}${p2(now.minute)}.csv',
      confirmButtonText: 'Export',
    );
    if (loc == null) return;
    try {
      await File(loc.path).writeAsString(predictionsCsv(predictionLog));
      _rememberDir(loc.path);
      notice = 'Saved ${fmtInt(predictionLog.length)} predictions to ${loc.path}.';
    } catch (e) {
      error = "Couldn't write the predictions file: $e";
    }
    notifyListeners();
  }

  void clearPredictions() {
    calls.clear();
    predictionLog.clear();
    notifyListeners();
  }

  // ── live counters (never past visibleCursor) ────────────────────────
  int get openGaps {
    final c = visibleCursor;
    return zones.where((z) => z.formed <= c && z.end > c).length;
  }

  Iterable<Zone> get _resolvedInReplay {
    final c = visibleCursor;
    return zones.where((z) => z.end <= c && z.end >= replayStart);
  }

  int get resolvedCount => _resolvedInReplay.length;

  String get runningBounceRate {
    var b = 0, r = 0;
    for (final z in _resolvedInReplay) {
      if (z.ev.outcome == EvOutcome.timeout) continue;
      r++;
      if (z.ev.outcome == EvOutcome.bounce) b++;
    }
    return r == 0 ? '—' : '${(b / r * 100).toStringAsFixed(1)}%';
  }

  /// Only calls whose outcome is already visible at the cursor are scored on screen.
  String get score {
    var c = 0, t = 0;
    final cur = visibleCursor;
    for (final r in predictionLog) {
      final z = _zoneById['${r.formationTime}|${r.dir}'];
      if (z == null || z.end > cur) continue;
      t++;
      if (r.correct) c++;
    }
    return '$c/$t';
  }

  // ── demo presets (bundled sample data) ──────────────────────────────
  void applyPreset(int p) {
    series.clear();
    events = const [];
    _byId.clear();
    baseline = null;
    eventsTf = null;
    baseTf = null;
    isSample = false;
    calls.clear();
    predictionLog.clear();
    selected = null;
    drill = null;
    error = null;
    notice = null;
    mode = Mode.explore;
    rightOpen = bottomOpen = leftOpen = focus = selectMode = playing = predict = false;
    peek = null;
    pending = null;
    if (p == 5) {
      _applyFilters();
      notifyListeners();
      return;
    }
    final c = generateSampleCandles();
    series['M15'] = c;
    baseTf = 'M15';
    timeframe = 'M15';
    isSample = true;
    events = demoEvents(c, k: k, buffer: failBuffer);
    eventColumns = const {'disp_q', 'htf_trend', 'sweep'};
    fakeEvents = const [];
    controlEvents = const [];
    holdoutRevealedAt = null;
    _byId.addEntries(events.map((e) => MapEntry(e.id, e)));
    mapEvents(events, c);
    eventsTf = 'M15';
    bookmarks = BookmarkStore(null);
    _applyFilters();
    _resetView();
    if (p == 2) {
      rightOpen = bottomOpen = true;
      final e = zones.where((z) => z.formed >= 150 && z.formed <= 166);
      selected = e.isEmpty ? null : e.first.ev.id;
    }
    if (p == 3) {
      mode = Mode.replay;
      cursor = min(176, n - 1);
      replayStart = 0;
      viewStart = clampV(cursor - 105);
    }
    if (p == 4 && zones.isNotEmpty) {
      final z = zones.last;
      mode = Mode.replay;
      predict = true;
      cursor = max(0, z.touch - 1);
      peek = z.touch;
      pending = z.ev.id;
      replayStart = 60;
      viewStart = clampV(cursor - 128);
      var i = 0;
      for (final x in zones) {
        if (x != z && x.formed >= 60 && x.end <= cursor) {
          final call = (x.ev.outcome == EvOutcome.bounce) != (i == 2) ? 'bounce' : 'break';
          calls[x.ev.id] = call;
          predictionLog.add(PredictionRecord.of(x.ev, call, DateTime.now().toUtc()));
          i++;
        }
      }
    }
    _syncTimer();
    notifyListeners();
  }

  void _set(VoidCallback f) {
    f();
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    bookmarks.save();
    hover.dispose();
    pulseTick.dispose();
    super.dispose();
  }
}
