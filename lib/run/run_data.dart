import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../util/fastparse.dart';
import 'protection.dart';

/// Shown to the user as-is.
class RunLoadError implements Exception {
  const RunLoadError(this.message);
  final String message;
  @override
  String toString() => message;
}

String _sep = Platform.pathSeparator;
String joinPath(String dir, String name) => dir.endsWith(_sep) ? '$dir$name' : '$dir$_sep$name';
String baseName(String p) => p.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty).lastOrNull ?? p;
String stemOf(String p) {
  final b = baseName(p), i = b.lastIndexOf('.');
  return i > 0 ? b.substring(0, i) : b;
}

/// "2021-01-03 23:00:00" (engine output, UTC) → ms.
int? engineMs(Object? s) {
  if (s is! String) return null;
  final b = Uint8List.fromList(s.codeUnits);
  return parseTimeBytes(b, 0, b.length);
}

/// "2021-01-03" → ms of that UTC midnight.
int? dateMs(String? s) {
  if (s == null || s.length != 10) return null;
  final d = DateTime.tryParse('${s}T00:00:00Z');
  return d?.millisecondsSinceEpoch;
}

double? _d(Object? v) => v is num ? v.toDouble() : null;

/// One run directory's `run.json`, plus what the app knows about it (protected-period confirmation).
/// Every number here is the engine's.
class RunManifest {
  RunManifest({required this.dir, required this.json, required this.modifiedMs, this.confirmation});

  final String dir;
  final Map<String, dynamic> json;

  /// run.json's mtime: when the run finished ("date run").
  final int modifiedMs;
  final Confirmation? confirmation;

  String get runId => baseName(dir);
  Map<String, dynamic> get _strategy => (json['strategy'] as Map?)?.cast<String, dynamic>() ?? const {};
  Map<String, dynamic> get _range => (json['range'] as Map?)?.cast<String, dynamic>() ?? const {};
  Map<String, dynamic> get _data => (json['data'] as Map?)?.cast<String, dynamic>() ?? const {};
  Map<String, dynamic> get summary => (json['summary'] as Map?)?.cast<String, dynamic>() ?? const {};
  Map<String, dynamic> get model => (json['model'] as Map?)?.cast<String, dynamic>() ?? const {};
  Map<String, dynamic> get account => (json['account'] as Map?)?.cast<String, dynamic>() ?? const {};
  Map<String, dynamic> get profile => (json['profile'] as Map?)?.cast<String, dynamic>() ?? const {};

  /// The strategy's file name ("fvg_continuation"): protected periods and settings are keyed by it.
  String get strategyKey {
    final src = _strategy['source'];
    if (src is String && src.isNotEmpty) return stemOf(src);
    final spec = '${_strategy['spec'] ?? ''}';
    return spec.startsWith('builtin:') ? spec : stemOf(spec);
  }

  String get strategyName => '${_strategy['id'] ?? strategyKey}';
  String get strategyVersion => '${_strategy['version'] ?? ''}';

  /// Inputs given for this run (the overrides); the rest were the strategy's defaults.
  Map<String, String> get inputs => {for (final e in ((_strategy['inputs'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}'};
  Map<String, String> get inputsEffective =>
      {for (final e in ((_strategy['inputs_effective'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}'};

  String get dataPath => '${_data['path'] ?? ''}';
  String? get from => _range['from'] as String?;
  String? get to => _range['to'] as String?;
  int? get firstSimMs => engineMs(_range['first_simulated_bar']);
  int? get lastSimMs => engineMs(_range['last_simulated_bar']);
  String get result => '${json['result'] ?? ''}';
  bool get ok => result == 'ok';
  bool get zeroCost => json['zero_cost'] == true;
  List<String> get warnings => [for (final w in (json['warnings'] as List?) ?? const []) '$w'];
  String get equityTf => '${model['equity_tf'] ?? ''}';
  double? get netProfit => _d(summary['net_profit']);
  int? get trades => (summary['trades'] as num?)?.toInt();

  /// The simulated span (the first and last simulated M1 bars; the last one's ticks run to +59 s).
  (int, int)? get simSpan {
    final a = firstSimMs, b = lastSimMs;
    return a == null || b == null ? null : (a, b + 59000);
  }

  RunManifest withConfirmation(Confirmation c) => RunManifest(dir: dir, json: json, modifiedMs: modifiedMs, confirmation: c);
}

/// Reads `<dir>/run.json` and the confirmation file. Throws [RunLoadError].
RunManifest readManifest(String dir) {
  final f = File(joinPath(dir, 'run.json'));
  if (!f.existsSync()) throw RunLoadError('No run.json in $dir. The run may have been stopped before it finished.');
  try {
    final j = jsonDecode(f.readAsStringSync());
    if (j is! Map) throw const FormatException('not an object');
    return RunManifest(dir: dir, json: j.cast<String, dynamic>(), modifiedMs: f.lastModifiedSync().millisecondsSinceEpoch, confirmation: readConfirmation(dir));
  } on FormatException catch (e) {
    throw RunLoadError("run.json in ${baseName(dir)} couldn't be read: ${e.message}");
  }
}

/// One position, IN to OUT (trades.json).
class Trade {
  Trade(this.j)
      : openMs = engineMs(j['open_time']) ?? 0,
        closeMs = engineMs(j['close_time']) ?? 0;
  final Map<String, dynamic> j;
  final int openMs, closeMs;

  int get ticket => (j['ticket'] as num).toInt();
  bool get isBuy => j['type'] == 'buy';
  double get volume => _d(j['volume']) ?? 0;
  double get openPrice => _d(j['open_price']) ?? 0;
  double get closePrice => _d(j['close_price']) ?? 0;
  double get slInitial => _d(j['sl_initial']) ?? 0;
  double get tpInitial => _d(j['tp_initial']) ?? 0;
  double get slFinal => _d(j['sl_final']) ?? 0;
  double get tpFinal => _d(j['tp_final']) ?? 0;
  String get reason => '${j['reason'] ?? ''}';
  String get flags => '${j['flags'] ?? ''}';
  double get net => _d(j['net']) ?? 0;
  double? get r => _d(j['r_multiple']);
  String get comment => '${j['comment'] ?? ''}';
  String get openTime => '${j['open_time']}';
  String get closeTime => '${j['close_time']}';
  double? value(String k) => _d(j[k]);
}

/// MT5-style deal (deals.csv), kept as the engine's text plus parsed time.
class Deal {
  Deal(this.cells, this.ms);
  final List<String> cells;
  final int ms;
}

/// One drawings.jsonl event.
class DrawEvent {
  DrawEvent(this.ms, this.j);
  final int ms;
  final Map<String, dynamic> j;
  String get op => '${j['op']}';
  String get name => '${j['name']}';
}

/// One drawings.jsonl line (SPEC §7.4), or null for an empty or malformed line (a malformed line
/// can only come from a truncated file). Shared by runs and indicator outputs.
DrawEvent? parseDrawLine(String l) {
  if (l.isEmpty) return null;
  try {
    final j = (jsonDecode(l) as Map).cast<String, dynamic>();
    return DrawEvent(engineMs(j['time']) ?? 0, j);
  } catch (_) {
    return null;
  }
}

class JournalLine {
  const JournalLine(this.ms, this.text);
  final int ms;
  final String text;
}

class RunData {
  RunData({required this.manifest, required this.trades, required this.dealHeader, required this.deals, required this.drawings, required this.journal});
  final RunManifest manifest;
  final List<Trade> trades;
  final List<String> dealHeader;
  final List<Deal> deals;
  final List<DrawEvent> drawings;
  final List<JournalLine> journal;
}

/// Splits one CSV line written by the engine (fields quoted only when they hold , " or newline).
List<String> splitCsvLine(String line) {
  final out = <String>[];
  final b = StringBuffer();
  var q = false;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (q) {
      if (ch == '"') {
        if (i + 1 < line.length && line[i + 1] == '"') {
          b.write('"');
          i++;
        } else {
          q = false;
        }
      } else {
        b.write(ch);
      }
    } else if (ch == '"') {
      q = true;
    } else if (ch == ',') {
      out.add(b.toString());
      b.clear();
    } else {
      b.write(ch);
    }
  }
  out.add(b.toString());
  return out;
}

/// Loads every small output file of a finished run. Runs inside an isolate.
RunData loadRunFiles(String dir) {
  final m = readManifest(dir);
  String read(String name, {bool required = true}) {
    final f = File(joinPath(dir, name));
    if (!f.existsSync()) {
      if (required) throw RunLoadError('$name is missing from ${baseName(dir)}.');
      return '';
    }
    return f.readAsStringSync();
  }

  final trades = <Trade>[];
  final tj = read('trades.json');
  try {
    for (final t in (jsonDecode(tj) as List)) {
      trades.add(Trade((t as Map).cast<String, dynamic>()));
    }
  } catch (e) {
    throw RunLoadError("trades.json in ${baseName(dir)} couldn't be read: $e");
  }

  final dealLines = const LineSplitter().convert(read('deals.csv'));
  final header = dealLines.isEmpty ? <String>[] : splitCsvLine(dealLines.first);
  final it = header.indexOf('time');
  final deals = <Deal>[
    for (final l in dealLines.skip(1))
      if (l.isNotEmpty)
        () {
          final c = splitCsvLine(l);
          return Deal(c, it >= 0 && it < c.length ? engineMs(c[it]) ?? 0 : 0);
        }(),
  ];

  final drawings = <DrawEvent>[
    for (final l in const LineSplitter().convert(read('drawings.jsonl', required: false))) ?parseDrawLine(l),
  ];

  final journal = parseJournal(read('journal.txt', required: false));
  return RunData(manifest: m, trades: trades, dealHeader: header, deals: deals, drawings: drawings, journal: journal);
}

/// journal.txt: `[YYYY-MM-DD HH:MM:SS] message`; a line without a stamp keeps the previous one's.
List<JournalLine> parseJournal(String text) {
  final journal = <JournalLine>[];
  for (final l in const LineSplitter().convert(text)) {
    if (l.length > 22 && l.startsWith('[') && l[20] == ']') {
      journal.add(JournalLine(engineMs(l.substring(1, 20)) ?? 0, l.substring(22)));
    } else if (l.isNotEmpty) {
      journal.add(JournalLine(journal.isEmpty ? 0 : journal.last.ms, l));
    }
  }
  return journal;
}
