import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:strategy_lab/data/candles.dart';
import 'package:strategy_lab/data/candle_cache.dart';
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

/// Geist isn't bundled; on this machine the app falls back to Noto Sans, so widget tests measure with it.
Future<void> loadFallbackFont() async {
  const noto = '/usr/share/fonts/truetype/noto/NotoSans-Regular.ttf';
  if (!File(noto).existsSync()) return;
  for (final family in ['Geist', 'Noto Sans']) {
    await (FontLoader(family)..addFont(Future.value(ByteData.sublistView(File(noto).readAsBytesSync())))).load();
  }
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

/// A LabState with settings in a temp file and no engine started.
Future<LabState> testLab({AppState? chart}) async {
  final settings = await Settings.load(File('${tempDir().path}/settings.json'));
  return LabState(chart: chart ?? AppState(), settings: settings);
}

Candles m1Of(AppState s) => s.series['M1']!;
