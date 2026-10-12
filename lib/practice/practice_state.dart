import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../engine/engine_service.dart';
import '../run/protection.dart';
import '../state/app_state.dart';
import '../state/settings.dart';

/// The strategy key of practice runs (run.json strategy.spec), for protected periods and History.
const kPracticeKey = 'builtin:practice';

String _p2(int v) => v.toString().padLeft(2, '0');

/// `YYYY-MM-DD HH:MM:SS` UTC, the engine's time format.
String engineTime(int ms) {
  final t = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  return '${t.year}-${_p2(t.month)}-${_p2(t.day)} ${_p2(t.hour)}:${_p2(t.minute)}:${_p2(t.second)}';
}

int? parseEngineTime(Object? s) => s is String ? DateTime.tryParse('${s.replaceFirst(' ', 'T')}Z')?.millisecondsSinceEpoch : null;

double _d(Object? v) => (v as num?)?.toDouble() ?? 0;

/// The open position, as the engine reports it.
class PracticePosition {
  PracticePosition(Map j)
      : ticket = (j['ticket'] as num).toInt(),
        type = '${j['type']}',
        volume = _d(j['volume']),
        priceOpen = _d(j['price_open']),
        openMs = parseEngineTime(j['time_open']) ?? 0,
        sl = _d(j['sl']),
        tp = _d(j['tp']),
        profit = _d(j['profit']),
        swap = _d(j['swap']),
        commission = _d(j['commission']);
  final int ticket, openMs;
  final String type;
  final double volume, priceOpen, sl, tp, profit, swap, commission;
  bool get buy => type == 'buy';
}

/// A pending order, as the engine reports it.
class PracticeOrder {
  PracticeOrder(Map j)
      : ticket = (j['ticket'] as num).toInt(),
        type = '${j['type']}',
        volume = _d(j['volume']),
        price = _d(j['price']),
        sl = _d(j['sl']),
        tp = _d(j['tp']),
        expiration = j['expiration'] as String?,
        setupMs = parseEngineTime(j['time_setup']) ?? 0;
  final int ticket, setupMs;
  final String type;
  final double volume, price, sl, tp;
  final String? expiration;
  bool get buy => type.startsWith('buy');

  /// "Buy limit".
  String get label => '${type[0].toUpperCase()}${type.substring(1).replaceAll('_', ' ')}';
}

/// A closed trade (trades.json record).
class PracticeTrade {
  PracticeTrade(Map j)
      : ticket = (j['ticket'] as num).toInt(),
        type = '${j['type']}',
        volume = _d(j['volume']),
        openMs = parseEngineTime(j['open_time']) ?? 0,
        closeMs = parseEngineTime(j['close_time']) ?? 0,
        openPrice = _d(j['open_price']),
        closePrice = _d(j['close_price']),
        reason = '${j['reason']}',
        net = _d(j['net']),
        rMultiple = (j['r_multiple'] as num?)?.toDouble();
  final int ticket, openMs, closeMs;
  final String type, reason;
  final double volume, openPrice, closePrice, net;
  final double? rMultiple;
  bool get buy => type == 'buy';
}

/// The order ticket being filled in (MT5's order window).
class OrderTicket {
  String kind = 'market'; // market / limit / stop
  String sizeMode = 'lots'; // lots / risk
  String size = '0.10';
  String price = '', sl = '', tp = '', expiration = '';
}

/// A practice session (SPEC §7.8, M8): manual trading in replay, executed by the engine (`hummer
/// session` through serve). The replay cursor drives the engine forward; orders are possible only at
/// the newest point reached ([reachedMs]); nothing is computed here, every number is the engine's.
class PracticeState extends ChangeNotifier {
  PracticeState({required this.engine, required this.chart, required this.settings, required this.openData, required this.openRunDir}) {
    chart.addListener(_onChart);
  }

  final EngineService engine;
  final AppState chart;
  final Settings settings;

  /// Opens the data file's chart (LabState.openDataChart); false when it couldn't.
  final Future<bool> Function(String path) openData;

  /// Opens a finished run folder (LabState: refresh History, then open it).
  final Future<void> Function(String dir) openRunDir;

  String? sessionId, out, dataFile, from;
  Map<String, String> options = const {};
  bool starting = false, ready = false, busy = false;
  String? error, message;
  bool messageIsError = false;

  /// The newest chart "now" the engine has processed (ms). Trading only there.
  int reachedMs = 0;
  int? _wantMs;

  // the engine's state
  int? engineMs;
  double balance = 0, equity = 0, margin = 0, freeMargin = 0, marginLevel = 0, profit = 0;
  PracticePosition? position;
  List<PracticeOrder> orders = const [];
  final List<PracticeTrade> trades = [];
  final List<String> journal = [];

  final OrderTicket ticket = OrderTicket();

  /// Set when the cursor reached a protected period without a logged confirmation (the cursor is held
  /// before it until the user confirms).
  ProtectedPeriod? needsConfirm;

  /// A price field waiting for a click on the chart ("price", "sl" or "tp").
  String? picking;

  Completer<void>? _ready;
  bool _disposed = false;

  bool get active => sessionId != null && ready;
  bool get atHead => active && chart.isReplay && !chart.selectMode && chart.nowMs >= reachedMs;
  bool get canTrade => atHead && !busy && engineMs != null && needsConfirm == null;

  /// The saved session, if any (resumable).
  Map<String, dynamic>? get saved => settings.practice;

  // ── lifecycle ───────────────────────────────────────────────────────
  /// Starts a new session at [startDate] (YYYY-MM-DD) on [data], or resumes the saved one.
  /// [confirmed]: the protected period the user confirmed for this start (logged in the session folder).
  Future<void> start({
    required String data,
    required String startDate,
    Map<String, String> opts = const {},
    bool resume = false,
    ProtectedPeriod? confirmed,
  }) async {
    if (starting || sessionId != null) return;
    final s = saved;
    final dir = resume && s != null ? '${s['out']}' : '${settings.runsDir}/practice_${_stamp(DateTime.now().toUtc())}';
    starting = true;
    error = null;
    message = null;
    _clearState();
    _publish();
    try {
      // The chart opens straight into replay at the newest point the user may see: just before the start
      // date, or where a resumed session was (nothing later is ever painted).
      final resumeAt = resume ? (s?['reached_ms'] as num?)?.toInt() : null;
      final atMs = resumeAt ?? DateTime.parse('${startDate}T00:00:00Z').millisecondsSinceEpoch - 1000;
      chart.lockPractice(atMs);
      if (!await openData(data)) throw StateError('the data file could not be opened');
      final r = (await engine.request('start_session', {
        'data': data,
        'from': startDate,
        'out': dir,
        'profile': settings.profilePath,
        if (opts.isNotEmpty) 'options': opts,
      })) as Map;
      sessionId = '${r['session_id']}';
      out = '${r['out']}';
      dataFile = data;
      from = startDate;
      options = Map.of(opts);
      _ready = Completer<void>();
      await _ready!.future.timeout(const Duration(minutes: 2));
      if (confirmed != null) {
        await writeConfirmation(out!, kind: 'start', strategy: kPracticeKey, period: confirmed, runFrom: startDate, runTo: null);
      }
      reachedMs = resumeAt ?? 0;
      settings.practice = {'out': out, 'data': data, 'from': startDate, 'options': options, 'reached_ms': reachedMs};
      settings.changed();
      _onChart(); // the engine catches up with the cursor
    } on EngineError catch (e) {
      error = e.code == 'unknown_method' ? 'This engine has no practice sessions. Build or update the engine.' : e.message;
      await _endSession();
    } catch (e) {
      error = '$e';
      await _endSession();
    } finally {
      starting = false;
      _publish();
    }
  }

  /// Stops the worker; the session folder stays resumable.
  Future<void> pause([String? why]) async {
    final id = sessionId;
    if (id == null) return;
    await _endSession();
    if (why != null) message = why;
    try {
      await engine.request('stop_session', {'session_id': id});
    } catch (_) {
      // already gone
    }
    _publish();
  }

  /// Ends the session: the engine closes the position, cancels orders and writes the run, which opens.
  Future<void> finish() async {
    if (!active || busy) return;
    busy = true;
    _publish();
    try {
      final r = (await _call('finish', const {})) as Map;
      final dir = '${r['out']}';
      settings.practice = null;
      settings.changed();
      await _endSession();
      await openRunDir(dir);
    } on EngineError catch (e) {
      _say(e.message, error: true);
    } finally {
      busy = false;
      _publish();
    }
  }

  /// The protected period a session starting on [startDate] would show (its first day or the
  /// history before it), or null.
  ProtectedPeriod? protectedAtStart(String startDate) {
    final p = settings.protectionFor(kPracticeKey);
    final d = DateTime.tryParse('${startDate}T00:00:00Z');
    if (p == null || d == null) return null;
    return p.overlaps(null, d.millisecondsSinceEpoch + 86400000 - 1) ? p : null;
  }

  /// Forget a saved session without resuming it (its folder stays on disk).
  void discardSaved() {
    settings.practice = null;
    settings.changed();
    _publish();
  }

  Future<void> _endSession() async {
    sessionId = null;
    ready = false;
    busy = false;
    _wantMs = null;
    needsConfirm = null;
    picking = null;
    chart.unlockPractice();
    if (!(_ready?.isCompleted ?? true)) _ready!.completeError(StateError('the session ended before it was ready'));
    _ready = null;
  }

  void _clearState() {
    engineMs = null;
    balance = equity = margin = freeMargin = marginLevel = profit = 0;
    position = null;
    orders = const [];
    trades.clear();
    journal.clear();
  }

  // ── engine events ───────────────────────────────────────────────────
  void onEvent(Map<String, dynamic> e) {
    final ev = '${e['event']}';
    if (ev == 'engine_exited') {
      if (sessionId != null) {
        _endSession();
        _say('The engine stopped. The session is saved: Resume continues it.', error: true);
      }
      return;
    }
    if (e['session_id'] != sessionId || sessionId == null) return;
    if (ev == 'session_ready') {
      _clearState();
      _apply(e['state'] as Map?);
      ready = true;
      if (!(_ready?.isCompleted ?? true)) _ready!.complete();
      _publish();
    } else if (ev == 'session_finished') {
      final status = '${e['status']}';
      if (status == 'failed') {
        final why = e['error'] ?? 'the session stopped';
        if (!(_ready?.isCompleted ?? true)) _ready!.completeError(StateError('$why'));
        _endSession();
        _say('The session stopped: $why. It is saved: Resume continues it.', error: true);
      } else if (sessionId != null) {
        _endSession();
      }
      _publish();
    }
  }

  void _apply(Map? st) {
    if (st == null) return;
    engineMs = parseEngineTime(st['time']);
    balance = _d(st['balance']);
    equity = _d(st['equity']);
    margin = _d(st['margin']);
    freeMargin = _d(st['free_margin']);
    marginLevel = _d(st['margin_level']);
    profit = _d(st['profit']);
    position = st['position'] is Map ? PracticePosition(st['position'] as Map) : null;
    orders = [for (final o in (st['orders'] as List?) ?? const []) PracticeOrder(o as Map)];
    for (final t in (st['trades'] as List?) ?? const []) {
      trades.add(PracticeTrade(t as Map));
    }
    for (final l in (st['journal'] as List?) ?? const []) {
      journal.add('$l');
    }
    if (journal.length > 500) journal.removeRange(0, journal.length - 500);
  }

  Future<dynamic> _call(String method, Map<String, dynamic> params) =>
      engine.request('session_call', {'session_id': sessionId, 'method': method, 'params': params});

  // ── the replay drives the engine ────────────────────────────────────
  void _onChart() {
    if (sessionId == null || !ready) return;
    if (chart.candlesPath != dataFile || chart.run != null || !chart.loaded) {
      pause('The chart changed, so the practice session was paused. Resume continues it.');
      return;
    }
    if (!chart.isReplay || chart.selectMode) return;
    final now = chart.nowMs;
    // A protected period (default 2024 on) is entered only after a logged confirmation.
    final p = settings.protectionFor(kPracticeKey);
    if (p != null && p.overlaps(now, now) && !_confirmed(p)) {
      final c = chart.candles!;
      var bar = c.lowerBound(p.fromMs) - 1;
      while (bar > 0 && c.endMs(bar) >= p.fromMs) {
        bar--;
      }
      needsConfirm = p;
      if (chart.playing) chart.togglePlay();
      chart.startAt(max(0, bar)); // re-enters here, now before the period
      return;
    }
    if (now > reachedMs) {
      _wantMs = max(_wantMs ?? 0, now);
      if (!busy) unawaited(_pump());
    }
    _publish();
  }

  bool _confirmed(ProtectedPeriod p) {
    final o = out;
    return o != null && (readConfirmation(o)?.covers(p) ?? false);
  }

  /// The user confirmed practising inside the protected period: logged in the session folder.
  Future<void> confirmProtected() async {
    final p = needsConfirm, o = out;
    if (p == null || o == null) return;
    await writeConfirmation(o, kind: 'start', strategy: kPracticeKey, period: p, runFrom: from, runTo: null);
    needsConfirm = null;
    _publish();
  }

  void cancelProtected() {
    needsConfirm = null;
    _publish();
  }

  Future<void> _pump() async {
    busy = true;
    _publish();
    try {
      while (_wantMs != null && sessionId != null) {
        final to = _wantMs!;
        _wantMs = null;
        final st = await _call('advance', {'to': engineTime(to)});
        _apply(st as Map);
        if (to > reachedMs) reachedMs = to;
        final p = settings.practice;
        if (p != null) {
          settings.practice = {...p, 'reached_ms': reachedMs};
          settings.changed();
        }
      }
    } on EngineError catch (e) {
      _say(e.message, error: true);
    } finally {
      busy = false;
      _publish();
    }
  }

  /// Back to the newest point reached (where orders are possible).
  void backToLatest() {
    final c = chart.candles;
    if (c == null || !active) return;
    chart.startAt(max(0, c.barAt(reachedMs)));
  }

  // ── orders ──────────────────────────────────────────────────────────
  /// Market buy/sell, or a pending order from the ticket ([buy] picks the side).
  Future<void> submit(bool buy) async {
    final t = ticket;
    final size = t.sizeMode == 'lots' ? {'volume': t.size.trim()} : {'risk_percent': t.size.trim()};
    final p = <String, dynamic>{
      ...size,
      if (t.sl.trim().isNotEmpty) 'sl': t.sl.trim(),
      if (t.tp.trim().isNotEmpty) 'tp': t.tp.trim(),
    };
    if (t.kind == 'market') {
      await request(buy ? 'buy' : 'sell', p);
    } else {
      await request('place', {
        ...p,
        'type': '${buy ? 'buy' : 'sell'}_${t.kind}',
        'price': t.price.trim(),
        if (t.expiration.trim().isNotEmpty) 'expiration': _expiration(t.expiration.trim()),
      });
    }
  }

  /// "2024-03-05 14:00" or "2024-03-05 14:00:00" -> the engine's format.
  static String _expiration(String s) => RegExp(r'^\d{4}-\d\d-\d\d \d\d:\d\d$').hasMatch(s) ? '$s:00' : s;

  Future<void> modifyPosition(double sl, double tp) => request('modify_position', {'sl': _px(sl), 'tp': _px(tp)});
  Future<void> closePosition() => request('close_position', const {});
  Future<void> cancelOrder(int ticket) => request('cancel_order', {'ticket': ticket});
  Future<void> modifyOrder(PracticeOrder o, {double? price, double? sl, double? tp}) => request('modify_order', {
        'ticket': o.ticket,
        'price': _px(price ?? o.price),
        'sl': _px(sl ?? o.sl),
        'tp': _px(tp ?? o.tp),
        'expiration': o.expiration,
      });

  /// A chart price as the order price text: the symbol's 3 digits (the engine checks the tick grid).
  static String _px(double v) => v <= 0 ? '0' : v.toStringAsFixed(3);
  static String priceText(double v) => _px(v);

  /// Sends one trading request; the engine executes it on the next tick and answers with its retcode.
  Future<void> request(String method, Map<String, dynamic> params) async {
    if (!canTrade) return;
    busy = true;
    message = null;
    _publish();
    try {
      final r = (await _call(method, params)) as Map;
      _apply(r['state'] as Map?);
      final req = r['request'] as Map?;
      final code = (req?['retcode'] as num?)?.toInt();
      if (code != null && code != 10009) {
        final why = journal.isNotEmpty ? journal.last.replaceFirst(RegExp(r'^\[[^\]]*\] '), '') : '${req?['comment']}';
        _say(why, error: true);
      }
    } on EngineError catch (e) {
      _say(e.message, error: true);
    } finally {
      busy = false;
      _publish();
    }
  }

  /// A click on the chart while a price field waits for one.
  void pickPrice(double price) {
    final f = picking;
    if (f == null) return;
    final v = _px(price);
    if (f == 'price') ticket.price = v;
    if (f == 'sl') ticket.sl = v;
    if (f == 'tp') ticket.tp = v;
    picking = null;
    _publish();
  }

  void startPicking(String? field) {
    picking = picking == field ? null : field;
    _publish();
  }

  void setTicket(void Function(OrderTicket t) f) {
    f(ticket);
    _publish();
  }

  void _say(String m, {bool error = false}) {
    message = m;
    messageIsError = error;
  }

  void clearMessage() {
    message = null;
    _publish();
  }

  /// A random weekday at least 30 days into [c] and 30 days before its end, outside protected periods.
  static DateTime? randomStart(int firstMs, int lastMs, ProtectedPeriod? p, [Random? rng]) {
    final r = rng ?? Random();
    const day = 86400000;
    final a = firstMs + 30 * day, b = lastMs - 30 * day;
    if (b <= a) return null;
    for (var k = 0; k < 200; k++) {
      final t = DateTime.fromMillisecondsSinceEpoch(a + (r.nextDouble() * (b - a)).floor(), isUtc: true);
      final d = DateTime.utc(t.year, t.month, t.day);
      if (d.weekday > 5) continue;
      if (p != null && p.overlaps(d.millisecondsSinceEpoch, d.millisecondsSinceEpoch + day - 1)) continue;
      return d;
    }
    return null;
  }

  static String _stamp(DateTime t) => '${t.year}${_p2(t.month)}${_p2(t.day)}-${_p2(t.hour)}${_p2(t.minute)}${_p2(t.second)}';

  void _publish() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    chart.removeListener(_onChart);
    super.dispose();
  }
}
