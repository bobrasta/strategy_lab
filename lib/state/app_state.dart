import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';

import '../chart/chart_geometry.dart';
import '../chart/chart_layer.dart';
import '../data/candles.dart';
import '../data/events.dart';
import '../data/loaders.dart';
import '../data/resample.dart';
import '../run/run_view.dart';

enum Mode { explore, replay }

/// What the right drawer shows: MT5's Strategy Tester or its Navigator → Indicators.
enum RightPanel { tester, indicators, practice }

/// Result-drawer tabs, after MT5's Strategy Tester.
enum ResultsTab { backtest, graph, trades, deals, journal, history, build }

class HoverInfo {
  const HoverInfo(this.bar, this.y);
  final int bar;
  final double y;
}

const kSpeeds = [1, 2, 5, 10, 25, 50, 100];

final _csv = XTypeGroup(label: 'CSV', extensions: const ['csv']);

// Top-level so the isolate closures capture only their arguments.
Future<Candles> _resampleIso(Candles src, int minutes) => Isolate.run(() => resample(src, minutes));
Future<EventsParse> _parseEventsIso(String path) => Isolate.run(() => parseEventsFile(path));

/// The chart: candles of the open run's data file, the view, replay, and the layers' inputs.
/// [visibleCursor] is the only "now"; nothing after it is drawn, listed or read.
class AppState extends ChangeNotifier {
  // ── data ────────────────────────────────────────────────────────────
  final Map<String, Candles> series = {}; // per timeframe, all cut at the run's end
  String? baseTf;
  String timeframe = 'M15';
  String? candlesPath;

  /// The open run (results, equity, drawings). Null when no run is open (no chart, or a data
  /// file shown on its own for indicators).
  RunView? run;

  /// One layer per attached indicator (set by the Indicators state), drawn after the fixed ones.
  List<ChartLayer> indicatorLayers = const [];

  /// The practice session's layer (its trades, position and orders), drawn last.
  ChartLayer? practiceLayer;

  /// A practice session holds the chart in replay (M8): the chart (re)opens in replay with nothing after
  /// this instant, and Explore and the select-a-bar mode (which show every bar) are off until it ends.
  int? practiceAtMs;
  bool get practiceLock => practiceAtMs != null;

  // FVG study overlay (optional; zones from fvg_events.csv, outcomes from Python).
  List<FvgEvent> events = const [];
  String? eventsPath, eventsTf;
  List<Zone> zones = const [];
  DateTime? holdoutRevealedAt;
  bool get holdoutLocked => holdoutRevealedAt == null;
  bool get zonesOnChart => eventsTf != null && timeframe == eventsTf;

  // ── ui ──────────────────────────────────────────────────────────────
  String? busy, error, notice;
  Mode mode = Mode.explore;
  RightPanel rightPanel = RightPanel.tester;
  bool leftOpen = false, rightOpen = false, bottomOpen = false, bottomTall = false, focus = false;
  ResultsTab tab = ResultsTab.backtest;
  bool selectMode = false, jumpOpen = false, playing = false;
  int zoom = 150, viewStart = 0, cursor = 0, replayStart = 0, speed = 5;

  /// Manual price scale on top of autoscale (which only ever reads bars ≤ cursor).
  double priceZoom = 1, priceShift = 0;
  bool get priceManual => priceZoom != 1 || priceShift != 0;

  /// Selected trade (position ticket).
  int? selectedTrade;
  final Set<String> layersOn = {'trades', 'drawings', 'fvg'};

  final hover = ValueNotifier<HoverInfo?>(null);
  Timer? _timer;
  final Stopwatch _sw = Stopwatch();
  int _done = 0;

  Candles? get candles => series[timeframe];
  int get n => candles?.length ?? 0;
  bool get loaded => n > 0;
  bool get isReplay => mode == Mode.replay;

  /// The only "now". Nothing right of it may be drawn or read.
  int get visibleCursor => isReplay && !selectMode ? cursor : n - 1;

  /// Last instant knowable at the cursor: the last tick of the cursor bar (+59 s of its last M1 bar).
  int get nowMs => loaded ? candles!.endMs(visibleCursor) : 0;

  DateTime timeOf(int i) {
    final c = candles;
    if (c == null || c.length == 0) return DateTime.utc(2000);
    if (i < c.length) return c.time(max(0, i));
    return c.time(c.length - 1).add(Duration(minutes: c.minutes * (i - c.length + 1)));
  }

  int clampV(int v) => v.clamp(0, max(0, n - zoom)).toInt();
  bool tfAvailable(String tf) {
    final b = baseTf;
    if (b == null) return false;
    final m = tfMinutes(tf), bm = tfMinutes(b);
    return m >= bm && m % bm == 0;
  }

  // ── run + candles ───────────────────────────────────────────────────
  /// Shows [bySeries] (the run's data file cut at the run's end: the base series plus any
  /// resampled ones, built off the UI isolate) with [view]'s results.
  Future<void> showRun(RunView view, Map<String, Candles> bySeries, String path, {String? tf}) => _show(view, bySeries, path, tf: tf);

  /// Shows a data file's candles without a run (for indicators): the whole file.
  Future<void> showData(Map<String, Candles> bySeries, String path) => _show(null, bySeries, path, tf: timeframe);

  Future<void> _show(RunView? view, Map<String, Candles> bySeries, String path, {String? tf}) async {
    if (practiceLock) {
      // Never a frame of the whole file: replay on the first bar until the cursor is placed below.
      mode = Mode.replay;
      selectMode = false;
      playing = false;
      cursor = 0;
      _syncTimer();
    } else {
      _exitReplayQuiet();
    }
    run?.dispose();
    run = view;
    selectedTrade = null;
    final m1 = bySeries.values.reduce((a, b) => a.minutes <= b.minutes ? a : b);
    series
      ..clear()
      ..addAll(bySeries);
    baseTf = m1.tf;
    candlesPath = path;
    final want = tf != null && kTimeframes.contains(tf) && tfAvailable(tf) ? tf : (tfAvailable('M15') ? 'M15' : m1.tf);
    final c = await _ensureTf(want);
    timeframe = c == null ? m1.tf : want;
    _resetView();
    _mapEvents();
    if (practiceAtMs != null) _lockAt(practiceAtMs!);
    notifyListeners();
  }

  /// Closes the run (e.g. a run whose results became protected).
  void closeRun() {
    _exitReplayQuiet();
    run?.dispose();
    run = null;
    series.clear();
    baseTf = null;
    candlesPath = null;
    selectedTrade = null;
    zones = const [];
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
    final wasReplay = isReplay && !selectMode;
    final nowT = nowMs;
    final centerMs = candles!.t[(viewStart + zoom ~/ 2).clamp(0, n - 1).toInt()];
    final c = await _ensureTf(tf);
    if (c == null) return;
    timeframe = tf;
    zoom = min(zoom, max(40, n));
    if (wasReplay) {
      // Keep "now": the last bar of the new timeframe whose end is ≤ the old now (never later).
      var i = c.barAt(nowT);
      while (i >= 0 && c.endMs(i) > nowT) {
        i--;
      }
      cursor = max(0, i);
      replayStart = min(replayStart, cursor);
      viewStart = clampV(cursor - (zoom * 0.7).floor());
    } else {
      viewStart = clampV(c.lowerBound(centerMs) - zoom ~/ 2);
      cursor = n - 1;
    }
    _rebuildZones();
    notifyListeners();
  }

  void _resetView() {
    priceZoom = 1;
    priceShift = 0;
    zoom = min(150, max(40, n));
    viewStart = clampV(n - zoom);
    cursor = max(0, n - 1);
  }

  void clearMessage() {
    error = null;
    notice = null;
    notifyListeners();
  }

  void showError(String msg) => _set(() => error = msg);
  void showNotice(String msg) => _set(() => notice = msg);

  // ── FVG overlay ─────────────────────────────────────────────────────
  Future<void> pickEvents() async {
    final f = await openFile(acceptedTypeGroups: [_csv], confirmButtonText: 'Load FVG events');
    if (f != null) await loadEvents(f.path);
  }

  Future<void> loadEvents(String path) async {
    busy = 'Loading FVG events…';
    notifyListeners();
    try {
      final r = await _parseEventsIso(path);
      events = r.events;
      eventsPath = path;
      holdoutRevealedAt = await _readHoldout(path);
      layersOn.add('fvg');
      _mapEvents();
      if (eventsTf == null && loaded) notice = "None of the FVG event times match this run's candles, so no zones are drawn.";
    } on LoadError catch (e) {
      error = e.message;
    } catch (e) {
      error = "The FVG events file couldn't be read: $e";
    } finally {
      busy = null;
      notifyListeners();
    }
  }

  void clearEvents() => _set(() {
        events = const [];
        eventsPath = null;
        eventsTf = null;
        zones = const [];
      });

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

  /// The study's hold-out outcomes stay hidden outside replay until revealed in FVG Lab.
  bool outcomeHidden(FvgEvent e) => holdoutLocked && e.isHoldout && !(isReplay && !selectMode);

  void _mapEvents() {
    eventsTf = null;
    if (events.isNotEmpty && baseTf != null) {
      for (final tf in ['M15', 'M5', 'H1', 'M1']) {
        final c = series[tf];
        if (c == null) continue;
        final miss = mapEvents(events, c);
        if (miss < events.length / 2) {
          eventsTf = tf;
          break;
        }
      }
    }
    _rebuildZones();
  }

  void _rebuildZones() {
    if (!zonesOnChart) {
      zones = const [];
      return;
    }
    mapEvents(events, candles!);
    zones = [
      for (final e in events)
        if (e.mapped) Zone(e, max(0, e.formedIdx - 2), e.formedIdx, e.touchIdx, e.endIdx),
    ];
  }

  // ── chrome ──────────────────────────────────────────────────────────
  void toggleLeft([bool? v]) => _set(() => leftOpen = v ?? !leftOpen);
  void toggleRight([bool? v]) => _togglePanel(RightPanel.tester, v);
  void toggleIndicators([bool? v]) => _togglePanel(RightPanel.indicators, v);
  void togglePractice([bool? v]) => _togglePanel(RightPanel.practice, v);
  bool panelOpen(RightPanel p) => rightOpen && rightPanel == p;

  /// The Tester and the Indicators share the right drawer; opening one replaces the other.
  void _togglePanel(RightPanel p, bool? v) => _set(() {
        final want = v ?? !panelOpen(p);
        if (want) {
          rightOpen = true;
          rightPanel = p;
        } else if (rightPanel == p) {
          rightOpen = false;
        }
      });

  void setIndicatorLayers(List<ChartLayer> layers) => _set(() => indicatorLayers = layers);
  void toggleBottom([bool? v]) => _set(() => bottomOpen = v ?? !bottomOpen);
  void toggleTall() => _set(() => bottomTall = !bottomTall);
  void showTab(ResultsTab t) => _set(() {
        tab = t;
        bottomOpen = true;
      });
  void toggleFocus() => _set(() => focus = !focus);
  void toggleLayer(String id) => _set(() => layersOn.contains(id) ? layersOn.remove(id) : layersOn.add(id));

  void lockPractice(int ms) {
    practiceAtMs = ms;
    if (loaded) _lockAt(ms);
    notifyListeners();
  }

  void unlockPractice() {
    if (practiceAtMs == null) return;
    practiceAtMs = null;
    notifyListeners();
  }

  /// Replay with the cursor on the last bar that ends by [ms].
  void _lockAt(int ms) {
    final c = candles!;
    var i = c.barAt(ms);
    while (i > 0 && c.endMs(i) > ms) {
      i--;
    }
    mode = Mode.replay;
    selectMode = false;
    playing = false;
    jumpOpen = false;
    cursor = max(0, i);
    replayStart = cursor;
    viewStart = clampV(cursor - (zoom * 0.7).floor());
    _syncTimer();
  }

  bool _lockedNotice() {
    if (!practiceLock) return false;
    showNotice('Practice keeps the chart in replay: pause or finish the session first.');
    return true;
  }

  void escape() => _set(() {
        selectMode = false;
        jumpOpen = false;
        leftOpen = false;
      });

  // ── view ────────────────────────────────────────────────────────────
  void zoomBy(double f) => _set(() {
        final end = viewStart + zoom;
        zoom = (zoom * f).round().clamp(40, max(40, n)).toInt();
        viewStart = clampV(end - zoom);
      });
  void fit() => _set(() {
        zoom = max(40, n);
        viewStart = 0;
        priceZoom = 1;
        priceShift = 0;
      });

  /// Gestures don't zoom out past this many bars (painting a whole M1 file per frame is too slow);
  /// Fit still shows everything.
  static const kMaxGestureZoom = 5000;

  /// Zooms by [f] (> 1 shows more bars) keeping the bar under [anchor]
  /// (0 = left edge … 1 = right edge of the plot) in place. Returns false at a limit.
  bool zoomAt(double f, double anchor) {
    if (!loaded) return false;
    final cap = max(40, min(n, max(kMaxGestureZoom, zoom)));
    final next = (zoom * f).round().clamp(40, cap).toInt();
    if (next == zoom) return false;
    const pad = ChartGeometry.rightPadBars;
    final bar = viewStart + anchor * (zoom + pad);
    zoom = next;
    viewStart = clampV((bar - anchor * (zoom + pad)).round());
    notifyListeners();
    return true;
  }

  void scalePrice(double f) => _set(() => priceZoom = (priceZoom * f).clamp(0.1, 20.0).toDouble());
  void shiftPrice(double by) => _set(() => priceShift = (priceShift + by).clamp(-50.0, 50.0).toDouble());
  void resetPriceScale() => _set(() {
        priceZoom = 1;
        priceShift = 0;
      });
  void pan(int d) => _set(() => viewStart = clampV(viewStart + d));

  // ── trades ──────────────────────────────────────────────────────────
  /// Bar index of [ms] on the current timeframe.
  int barOf(int ms) => candles?.barAt(ms) ?? -1;

  /// Selects a trade; [reveal] scrolls the chart to it (explore mode only, so replay never jumps ahead).
  void selectTrade(int? ticket, {bool reveal = false}) => _set(() {
        selectedTrade = ticket;
        final t = ticket == null ? null : run?.tradeByTicket(ticket);
        if (reveal && t != null && !isReplay) {
          final a = barOf(t.openMs), b = barOf(t.closeMs);
          if (b - a + 20 > zoom) zoom = min(max(40, b - a + 40), max(40, n));
          viewStart = clampV(a - ((zoom - (b - a)) * 0.4).floor());
        }
      });

  /// Replays [ticket] from 50 bars before its entry.
  void replayTrade(int ticket) {
    final t = run?.tradeByTicket(ticket);
    if (t == null || !loaded) return;
    mode = Mode.replay;
    selectedTrade = ticket;
    startAt(max(0, barOf(t.openMs) - 50));
  }

  // ── replay ──────────────────────────────────────────────────────────
  void setMode(Mode m) => m == Mode.replay ? enterReplay() : exitReplay();

  void enterReplay() {
    if (isReplay || !loaded || practiceLock) return;
    mode = Mode.replay;
    selectMode = true;
    playing = false;
    cursor = n - 1;
    hover.value = null;
    _syncTimer();
    notifyListeners();
  }

  void _exitReplayQuiet() {
    mode = Mode.explore;
    selectMode = false;
    playing = false;
    jumpOpen = false;
    _syncTimer();
  }

  void exitReplay() {
    if (_lockedNotice()) return;
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
    jumpOpen = false;
    viewStart = clampV(cursor - (zoom * 0.7).floor());
    _syncTimer();
    notifyListeners();
  }

  void toggleSelect() {
    if (_lockedNotice()) return;
    selectMode = !selectMode;
    playing = false;
    jumpOpen = false;
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

  void togglePlay() {
    if (!isReplay || selectMode) return;
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

  void toStart() {
    cursor = replayStart;
    playing = false;
    viewStart = clampV(cursor - (zoom * 0.7).floor());
    _syncTimer();
    notifyListeners();
  }

  void _advance(int steps) {
    if (!isReplay || selectMode || !loaded) return;
    final next = min(n - 1, cursor + steps);
    if (next >= n - 1) {
      playing = false;
      _syncTimer();
    }
    cursor = next;
    viewStart = _follow(cursor);
    notifyListeners();
  }

  void step(int d) {
    if (!isReplay || selectMode || !loaded) return;
    if (d > 0) {
      _advance(d);
      return;
    }
    cursor = max(0, cursor + d);
    viewStart = _follow(cursor);
    notifyListeners();
  }

  /// N / Shift+→: the next bar where a trade opens or closes.
  void nextTrade() {
    final r = run;
    if (!isReplay || selectMode || !loaded || r == null) return;
    int? best;
    for (final t in r.trades) {
      for (final ms in [t.openMs, t.closeMs]) {
        final b = barOf(ms);
        if (b > cursor && (best == null || b < best)) best = b;
      }
      if (best != null && barOf(t.openMs) > best) break; // trades are in open order
    }
    if (best == null) return;
    cursor = best;
    viewStart = _follow(cursor);
    notifyListeners();
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

  void _set(VoidCallback f) {
    f();
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    run?.dispose();
    hover.dispose();
    super.dispose();
  }
}

String siblingPath(String path, String name) {
  final i = path.lastIndexOf(RegExp(r'[\\/]'));
  return i < 0 ? name : '${path.substring(0, i + 1)}$name';
}
