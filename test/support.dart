import 'dart:io';

/// The research folder. Override with FXDATA_DIR; tests that need it skip when it's missing.
final String fxdataDir = Platform.environment['FXDATA_DIR'] ?? '/home/bob/Documents/fxdata';

String fx(String name) => '$fxdataDir${Platform.pathSeparator}$name';

const kM15 = 'xauusd_m15_2021-01-01_2026-01-01.csv';
const kM1 = 'xauusd_m1_2021-01-01_2026-01-01.csv';

/// A `skip:` reason when any of [names] is missing from [fxdataDir], else null (run).
String? skipUnlessFxdata(List<String> names) {
  final missing = names.where((n) => !File(fx(n)).existsSync()).toList();
  return missing.isEmpty ? null : 'fxdata not found: ${missing.join(', ')} in $fxdataDir (set FXDATA_DIR to run)';
}

/// Writes [text] to a fresh temp folder and returns the file path.
String writeTemp(String name, String text, {Directory? dir}) {
  final d = dir ?? Directory.systemTemp.createTempSync('fvg_lab_test_');
  final f = File('${d.path}${Platform.pathSeparator}$name')..writeAsStringSync(text);
  return f.path;
}

String _p2(int v) => v.toString().padLeft(2, '0');
String key(DateTime t) => '${t.year}-${_p2(t.month)}-${_p2(t.day)} ${_p2(t.hour)}:${_p2(t.minute)}:${_p2(t.second)}';

/// [n] M15 bars from [start] (UTC), flat around 100 unless [ohlc] overrides a bar.
String candlesCsv(int n, {DateTime? start, Map<int, List<double>> ohlc = const {}}) {
  final t0 = start ?? DateTime.utc(2022, 3, 1);
  final b = StringBuffer('time,open,high,low,close,volume\n');
  for (var i = 0; i < n; i++) {
    final v = ohlc[i] ?? [100.0, 100.5, 99.5, 100.0];
    b.writeln('${key(t0.add(Duration(minutes: 15 * i)))},${v[0]},${v[1]},${v[2]},${v[3]},1.0');
  }
  return b.toString();
}

const eventsHeader = 'time,touch_time,end_time,edge,far,dir,gap_atr,age,max_wick,max_close,outcome,bars,scenario,size_q';
