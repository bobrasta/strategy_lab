import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:strategy_lab/data/candles.dart';
import 'package:strategy_lab/data/candle_cache.dart';
import 'package:strategy_lab/engine/engine_service.dart';
import 'package:strategy_lab/run/equity_store.dart';
import 'package:strategy_lab/run/run_data.dart';
import 'package:strategy_lab/run/run_view.dart';
import 'package:strategy_lab/state/app_state.dart';
import 'package:strategy_lab/state/lab_state.dart';
import 'package:strategy_lab/state/settings.dart';

/// The research folder. Override with FXDATA_DIR; tests that need it skip when it's missing.
final String fxdataDir = Platform.environment['FXDATA_DIR'] ?? '/home/bob/Documents/fxdata';

String fx(String name) => '$fxdataDir${Platform.pathSeparator}$name';

const kM15 = 'xauusd_m15_2021-01-01_2026-10-08.csv';
const kM1 = 'xauusd_m1_2021-01-01_2026-10-08.csv';

/// The engine repo (for tests that run the real engine); they skip when its binary is missing.
final String engineRepo = Platform.environment['HUMMER_REPO'] ?? '/home/bob/projects/hummer-engine';
String get engineBinary => '$engineRepo/build/release/hummer';
String? skipUnlessEngine() => File(engineBinary).existsSync() ? null : 'engine binary not found at $engineBinary (set HUMMER_REPO)';

/// A `skip:` reason when any of [names] is missing from [fxdataDir], else null (run).
String? skipUnlessFxdata(List<String> names) {
  final missing = names.where((n) => !File(fx(n)).existsSync()).toList();
  return missing.isEmpty ? null : 'fxdata not found: ${missing.join(', ')} in $fxdataDir (set FXDATA_DIR to run)';
}

Directory tempDir() => Directory.systemTemp.createTempSync('strategy_lab_test_');

/// Writes [text] to a fresh temp folder and returns the file path.
String writeTemp(String name, String text, {Directory? dir}) {
  final d = dir ?? tempDir();
  final f = File('${d.path}${Platform.pathSeparator}$name')..writeAsStringSync(text);
  return f.path;
}

String _p2(int v) => v.toString().padLeft(2, '0');
String key(DateTime t) => '${t.year}-${_p2(t.month)}-${_p2(t.day)} ${_p2(t.hour)}:${_p2(t.minute)}:${_p2(t.second)}';

/// [n] bars of [minutes] from [start] (UTC), flat around 100 unless [ohlc] overrides a bar.
String candlesCsv(int n, {DateTime? start, int minutes = 15, Map<int, List<double>> ohlc = const {}}) {
  final t0 = start ?? DateTime.utc(2022, 3, 1);
  final b = StringBuffer('time,open,high,low,close,volume\n');
  for (var i = 0; i < n; i++) {
    final v = ohlc[i] ?? [100.0, 100.5, 99.5, 100.0];
    b.writeln('${key(t0.add(Duration(minutes: minutes * i)))},${v[0]},${v[1]},${v[2]},${v[3]},1.0');
  }
  return b.toString();
}

const eventsHeader = 'time,touch_time,end_time,edge,far,dir,gap_atr,age,max_wick,max_close,outcome,bars,scenario,size_q';

/// Widget tests measure text with the bundled Geist (assets/fonts, as in pubspec.yaml), not the
/// test font, so layout checks see the app's real text widths.
Future<void> loadAppFont() async {
  final loader = FontLoader('Geist');
  for (final w in ['Light', 'Regular', 'Medium', 'SemiBold', 'Bold']) {
    loader.addFont(Future.value(ByteData.sublistView(File('assets/fonts/Geist-$w.ttf').readAsBytesSync())));
  }
  await loader.load();
}

final t0 = DateTime.utc(2022, 3, 1);
int at(int minute, [int second = 0]) => t0.add(Duration(minutes: minute, seconds: second)).millisecondsSinceEpoch;
String atKey(int minute, [int second = 0]) => key(t0.add(Duration(minutes: minute, seconds: second)));

/// A hand-made run folder in the engine's formats, over 120 M1 bars from 2022-03-01 00:00 UTC:
/// - trade #1 buy  0.1 opened 00:10:00 @ 100.12, closed 00:40:20 @ 100.5 (tp),  net +30.00
/// - trade #3 sell 0.1 opened 01:05:00 @ 99.9,   closed 01:30:40 @ 100.1 (sl),  net -20.00
/// - equity: one row per M1 bar at +59 s (balance, equity = balance + profit), plus a row per deal
/// - drawings: zone "z" created 00:05 open-ended, moved at 00:50 to end 00:50, deleted 01:20;
///   marker "m" at 00:10; line "l" 00:20 → open end
/// - journal: lines at 00:10:00 and 01:05:00
/// [strategyKey] names the strategy file, so protected periods can apply.
Directory writeFakeRun({String strategyKey = 'fake', String from = '2022-03-01', String to = '2022-03-01', Directory? dir}) {
  final d = dir ?? tempDir();
  final candles = writeTemp('m1.csv', candlesCsv(120, minutes: 1, ohlc: {30: [100, 100.6, 99.4, 100.2], 70: [100, 100.3, 99.2, 99.8]}), dir: d);
  final run = Directory('${d.path}/run')..createSync();
  void w(String name, String text) => File('${run.path}/$name').writeAsStringSync(text);
  w('run.json', const JsonEncoder.withIndent(' ').convert({
    'engine': {'version': '0.1.0', 'git': 'test'},
    'strategy': {
      'id': 'Fake',
      'spec': '/x/build/strategies/$strategyKey.so',
      'inputs': {'Lots': '0.1'},
      'version': '1.0',
      'source': '/x/strategies/$strategyKey.cpp',
      'inputs_effective': {'Tf': 'M5', 'Lots': '0.1', 'Other': '3'},
    },
    'data': {'path': candles, 'bytes': File(candles).lengthSync(), 'bars': 120},
    'range': {'from': from, 'to': to, 'first_simulated_bar': atKey(0), 'last_simulated_bar': atKey(119), 'bars': 120, 'ticks': 480},
    'profile': {'symbol': 'XAUUSD', 'costs': {'spread': 120, 'commission_per_lot_side': 3.5}},
    'zero_cost': false,
    'account': {'deposit': 10000.0, 'leverage': 100},
    'model': {'tick_path': 'nearest', 'ambiguity_rule': 'path', 'equity_tf': 'M1'},
    'warnings': [],
    'result': 'ok',
    'summary': {'net_profit': 10.0, 'trades': 2, 'wins': 1, 'losses': 1, 'profit_factor': 1.5, 'long_trades': 1, 'long_wins': 1, 'short_trades': 1, 'short_wins': 0},
  }));
  w('trades.json', jsonEncode([
    {'ticket': 1, 'type': 'buy', 'volume': 0.1, 'open_time': atKey(10), 'open_price': 100.12, 'close_time': atKey(40, 20), 'close_price': 100.5,
     'sl_initial': 99.6, 'tp_initial': 100.5, 'sl_final': 99.6, 'tp_final': 100.5, 'reason': 'tp', 'flags': '', 'net': 30.0, 'r_multiple': 0.6, 'comment': 'a'},
    {'ticket': 3, 'type': 'sell', 'volume': 0.1, 'open_time': atKey(65), 'open_price': 99.9, 'close_time': atKey(90, 40), 'close_price': 100.1,
     'sl_initial': 100.1, 'tp_initial': 0, 'sl_final': 100.1, 'tp_final': 0, 'reason': 'sl', 'flags': 'GAP', 'net': -20.0, 'r_multiple': -1.0, 'comment': 'b'},
  ]));
  w('deals.csv', 'ticket,order,position,time,type,entry,volume,price,magic,reason,commission,swap,profit,balance,comment\n'
      '1,1,1,${atKey(10)},buy,in,0.1,100.12,1,expert,-0.35,0,0,9999.65,"a, quoted"\n'
      '2,2,1,${atKey(40, 20)},sell,out,0.1,100.5,1,tp,-0.35,0,30.35,10029.65,[tp 100.500]\n'
      '3,3,3,${atKey(65)},sell,in,0.1,99.9,1,expert,-0.35,0,0,10029.3,b\n'
      '4,4,3,${atKey(90, 40)},buy,out,0.1,100.1,1,sl,-0.35,0,-19.3,10010,[sl 100.100]\n');
  final eq = StringBuffer('time,kind,balance,equity,equity_min,margin,profit,drawdown,drawdown_pct\n');
  var bal = 10000.0;
  for (var m = 0; m < 120; m++) {
    void deal(int min, int sec, double b) {
      if (m == min) {
        bal = b;
        eq.writeln('${atKey(min, sec)},deal,$b,$b,$b,0,0,0,0');
      }
    }

    deal(10, 0, 9999.65);
    deal(40, 20, 10029.65);
    deal(65, 0, 10029.3);
    deal(90, 40, 10010);
    final open = (m >= 10 && m < 40) || (m >= 65 && m < 90);
    final profit = open ? (m - 9) * 1.0 : 0.0;
    eq.writeln('${atKey(m, 59)},bar,$bal,${bal + profit},${bal + profit - 0.5},${open ? 10 : 0},$profit,0.5,0.005');
  }
  w('equity.csv', eq.toString());
  w('drawings.jsonl', [
    jsonEncode({'time': atKey(5), 'op': 'create', 'name': 'z', 'kind': 'zone', 't1': atKey(3), 'p1': 100.4, 't2': null, 'p2': 100.2, 'color': 'green', 'label': 'FVG'}),
    jsonEncode({'time': atKey(10), 'op': 'create', 'name': 'm', 'kind': 'marker', 't1': atKey(10), 'p1': 100.12, 'color': 'blue', 'label': 'entry', 'shape': 'arrow_up'}),
    jsonEncode({'time': atKey(20), 'op': 'create', 'name': 'l', 'kind': 'line', 't1': atKey(20), 'p1': 100.3, 't2': null, 'p2': 100.3, 'color': 'amber', 'label': ''}),
    jsonEncode({'time': atKey(50), 'op': 'move', 'name': 'z', 'kind': 'zone', 't1': atKey(3), 'p1': 100.4, 't2': atKey(50), 'p2': 100.2}),
    jsonEncode({'time': atKey(80), 'op': 'delete', 'name': 'z', 'kind': 'zone'}),
  ].join('\n'));
  w('journal.txt', '[${atKey(10)}] market buy 0.10 XAUUSD -> deal #1\n[${atKey(65)}] market sell 0.10 XAUUSD -> deal #3\n');
  return run;
}

/// The fake run opened in a chart, without an engine (as LabState.openRun does it).
Future<AppState> openFakeRun(Directory run, {AppState? into}) async {
  final s = into ?? AppState();
  final data = loadRunFiles(run.path);
  final eq = EquityStore(joinPath(run.path, 'equity.csv'), scanEquityFile(joinPath(run.path, 'equity.csv')));
  await s.showRun(RunView(data, eq), runSeries(data.manifest.dataPath, null, data.manifest.lastSimMs), data.manifest.dataPath, tf: 'M1');
  return s;
}

/// A LabState with settings in a temp file and no engine started (or [engine], a [FakeEngine]).
Future<LabState> testLab({AppState? chart, EngineService? engine, Settings? settings}) async {
  final st = settings ?? await Settings.load(File('${tempDir().path}/settings.json'));
  return LabState(chart: chart ?? AppState(), settings: st, engine: engine);
}

Candles m1Of(AppState s) => s.series['M1']!;

/// A stand-in for `hummer serve`: requests go to [handler] (throw [EngineError] for an error
/// response), events are pushed with [emit]. Starts out ready; no process is involved.
class FakeEngine extends EngineService {
  FakeEngine(this.handler) : super(binary: '/nonexistent/hummer', workingDir: '/nonexistent') {
    status = EngineStatus.ready;
  }

  FutureOr<dynamic> Function(String method, Map<String, dynamic> params) handler;
  final calls = <(String, Map<String, dynamic>)>[];
  final _ev = StreamController<Map<String, dynamic>>.broadcast();

  @override
  Stream<Map<String, dynamic>> get events => _ev.stream;

  void emit(Map<String, dynamic> e) => _ev.add(e);

  List<Map<String, dynamic>> callsOf(String method) => [for (final c in calls) if (c.$1 == method) c.$2];

  @override
  Future<dynamic> request(String method, [Map<String, dynamic>? params]) async {
    calls.add((method, params ?? const {}));
    return handler(method, params ?? const {});
  }

  @override
  Future<void> shutdown({Duration wait = const Duration(seconds: 2)}) async {}

  @override
  void dispose() {
    _ev.close();
    super.dispose();
  }
}

/// The engine's answer to an indicator method before M7.
const unknownMethod = EngineError('unknown_method', "unknown method 'list_indicators'");

/// `list_indicators` rows.
List<Map<String, dynamic>> indicatorList([Map<String, String> status = const {'band': 'built', 'fvg': 'stale', 'donchian': 'not_built'}]) => [
      for (final e in status.entries)
        {'name': e.key, 'source': '/x/indicators/${e.key}.cpp', 'so': '/x/build/indicators/${e.key}.so', 'status': e.value, 'source_mtime': 1, 'so_mtime': 2},
    ];

/// `indicator_inputs` for the fake "band" indicator: {schema, plots}.
Map<String, dynamic> bandInputs() => {
      'schema': {
        'abi': 1,
        'name': 'Band',
        'kind': 'indicator',
        'inputs': [
          {'name': 'Tf', 'type': 'timeframe', 'default': 'M1', 'description': 'Timeframe'},
          {'name': 'Period', 'type': 'int', 'default': 5, 'description': 'Bars', 'min': 1, 'max': 500},
          {'name': 'Width', 'type': 'double', 'default': 0.1, 'description': 'Band width'},
        ],
      },
      'plots': bandPlots,
    };

const bandPlots = [
  {'index': 0, 'name': 'Mid', 'label': 'Middle', 'color': 'blue', 'style': 'solid', 'width': 1.5},
  {'index': 1, 'name': 'Upper', 'label': 'Upper band', 'color': 'amber', 'style': 'dashed', 'width': 1},
];

/// A hand-made indicator output folder (SPEC §7.7) over the fake run's 120 M1 bars
/// (2022-03-01 00:00 UTC on). Plot values are set when their bar completes (stamp = next bar open):
/// - plot 0 "Mid" (blue, solid): bar i → 100 + i/100 for i = 0..119, EMPTY_VALUE (empty) for bars
///   40..44; bar 60 repainted at 01:10:00 to 101.5 (first 100.6 at 01:01:00). Bar 119's value is
///   stamped 02:00:00, after the run's last tick (01:59:59), so it is never shown with the run.
/// - plot 1 "Upper" (amber, dashed): every 10th bar → 100.5
/// - objects: zone "g" created 00:12 (t1 00:10, 100.6/100.4, open-ended), moved at 00:30 to end
///   00:30, deleted 01:30, re-created 01:40 (t1 01:35, open-ended); marker "mk" at 00:20 (t1 00:19);
///   line "ln" created 00:50 (t1 00:45 → open end), a move of "nope" (doesn't exist) at 00:55
/// - journal: two lines
Directory writeFakeIndicator({Directory? dir, String dataPath = '/x/m1.csv', bool header = true}) {
  final d = dir ?? Directory('${tempDir().path}/band_0123456789abcdef')
    ..createSync(recursive: true);
  void w(String name, String text) => File('${d.path}/$name').writeAsStringSync(text);
  w('indicator.json', const JsonEncoder.withIndent(' ').convert({
    'kind': 'indicator',
    'engine': {'version': '0.2.0', 'git': 'test'},
    'indicator': {'name': 'Band', 'description': 'A test band', 'version': '1.0', 'path': '/x/build/indicators/band.so', 'sha256': 'ab'},
    'data': {'path': dataPath, 'sha256': 'cd'},
    'inputs': {'Tf': 'M1', 'Period': '5', 'Width': '0.1'},
    'from': null,
    'to': null,
    'tick_path': 'nearest',
    'plots': bandPlots,
    'counts': {'plot_records': 133, 'drawing_events': 8},
    'warnings': [],
    'cache_key': '0123456789abcdef0123456789abcdef',
  }));
  final rows = <(int, String)>[]; // (stamp ms, line) in emission order
  for (var i = 0; i < 120; i++) {
    final v = i >= 40 && i < 45 ? '' : '${100 + i / 100}';
    rows.add((at(i + 1), '${atKey(i + 1)},0,${atKey(i)},$v'));
    if (i % 10 == 0) rows.add((at(i + 1), '${atKey(i + 1)},1,${atKey(i)},100.5'));
    if (i == 69) rows.add((at(70), '${atKey(70)},0,${atKey(60)},101.5')); // the repaint, at 01:10:00
  }
  w('plots.csv', '${header ? 'stamp,plot,time,value\n' : ''}${rows.map((r) => r.$2).join('\n')}\n');
  w('drawings.jsonl', [
    jsonEncode({'time': atKey(12), 'op': 'create', 'name': 'g', 'kind': 'zone', 't1': atKey(10), 'p1': 100.6, 't2': null, 'p2': 100.4, 'color': 'green', 'label': 'gap up'}),
    jsonEncode({'time': atKey(20), 'op': 'create', 'name': 'mk', 'kind': 'marker', 't1': atKey(19), 'p1': 100.2, 'color': 'red', 'label': 'mark', 'shape': 'dot'}),
    jsonEncode({'time': atKey(30), 'op': 'move', 'name': 'g', 'kind': 'zone', 't1': atKey(10), 'p1': 100.6, 't2': atKey(30), 'p2': 100.4}),
    jsonEncode({'time': atKey(50), 'op': 'create', 'name': 'ln', 'kind': 'line', 't1': atKey(45), 'p1': 100.3, 't2': null, 'p2': 100.3, 'color': 'accent', 'label': ''}),
    jsonEncode({'time': atKey(55), 'op': 'move', 'name': 'nope', 'kind': 'line', 't1': atKey(50), 'p1': 1.0, 't2': null, 'p2': 1.0}),
    jsonEncode({'time': atKey(90), 'op': 'delete', 'name': 'g', 'kind': 'zone'}),
    jsonEncode({'time': atKey(100), 'op': 'create', 'name': 'g', 'kind': 'zone', 't1': atKey(95), 'p1': 101.0, 't2': null, 'p2': 100.8, 'color': 'red', 'label': 'gap down'}),
    '{"time":"2022-03-01 01:4', // a truncated last line is skipped
  ].join('\n'));
  w('journal.txt', '[${atKey(0)}] Band(5) on XAUUSD\n[${atKey(119)}] done\n');
  return d;
}

/// Waits (real time) until [cond] holds: isolate parsing and engine events are asynchronous.
Future<void> until(bool Function() cond, {String what = 'condition'}) async {
  final sw = Stopwatch()..start();
  while (!cond()) {
    if (sw.elapsedMilliseconds > 5000) throw StateError('timed out waiting for $what');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

/// A fake `hummer serve` with the M7 indicator methods. Every start_indicator answers with
/// [out] (a hand-made output folder); [onStart] can push events before the response goes out.
class M7Engine {
  M7Engine({this.supported = true}) {
    engine = FakeEngine(_handle);
  }

  final bool supported;
  late final FakeEngine engine;
  String out = writeFakeIndicator().path;
  bool cached = false;
  int _jobs = 0;
  void Function(String job)? onStart;
  Map<String, String> status = const {'band': 'built', 'fvg': 'stale', 'donchian': 'not_built'};

  dynamic _handle(String m, Map<String, dynamic> p) {
    if (!supported && (m.contains('indicator'))) throw unknownMethod;
    switch (m) {
      case 'list_strategies':
        return [];
      case 'list_indicators':
        return indicatorList(status);
      case 'indicator_inputs':
        return bandInputs();
      case 'start_indicator':
        final job = 'job-${++_jobs}';
        onStart?.call(job);
        return {'job_id': job, 'out': out, 'cached': cached};
      case 'stop_indicator':
        return {};
      case 'build_indicator':
        return {'build_id': 'build-1'};
    }
    throw EngineError('unknown_method', "unknown method '$m'");
  }

  void finish(String job, {String status = 'ok', bool cached = false, Map<String, dynamic> extra = const {}}) =>
      engine.emit({'event': 'indicator_finished', 'job_id': job, 'status': status, 'out': out, 'cached': cached, 'exit_code': status == 'ok' ? 0 : 1, ...extra});
}
