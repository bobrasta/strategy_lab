import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'candles.dart';
import 'events.dart';

/// Shown to the user as-is.
class LoadError implements Exception {
  const LoadError(this.message);
  final String message;
  @override
  String toString() => message;
}

class EventsParse {
  const EventsParse(this.events, this.skipped, this.columns);
  final List<FvgEvent> events;
  final int skipped;

  /// Lower-cased header names (plus canonical names for aliased condition columns).
  final Set<String> columns;
}

String _unq(String s) {
  var t = s.trim();
  if (t.length >= 2 && t.startsWith('"') && t.endsWith('"')) t = t.substring(1, t.length - 1);
  return t;
}

List<String> _split(String line) => line.split(',').map(_unq).toList();
List<String> _header(String line) => _split(line.replaceFirst('\uFEFF', '')).map((s) => s.toLowerCase()).toList();

String _readCsv(String path, String hint) {
  if (!path.toLowerCase().endsWith('.csv')) throw LoadError("That isn't a CSV file. $hint");
  final f = File(path);
  if (!f.existsSync()) throw const LoadError('That file no longer exists.');
  final bytes = f.readAsBytesSync();
  final probe = min(bytes.length, 4096);
  for (var i = 0; i < probe; i++) {
    if (bytes[i] == 0) throw LoadError("That file isn't plain text. $hint");
  }
  return utf8.decode(bytes, allowMalformed: true);
}

/// "2021-01-03 23:00:00" (UTC). Fast path for the downloader format, ISO fallback.
int? parseUtcMs(String s) {
  if (s.length >= 16 && s.length <= 19 && s.codeUnitAt(4) == 45 && s.codeUnitAt(7) == 45) {
    final y = int.tryParse(s.substring(0, 4)), mo = int.tryParse(s.substring(5, 7)), d = int.tryParse(s.substring(8, 10));
    final h = int.tryParse(s.substring(11, 13)), mi = int.tryParse(s.substring(14, 16));
    final sec = s.length >= 19 ? int.tryParse(s.substring(17, 19)) : 0;
    if (y != null && mo != null && d != null && h != null && mi != null && sec != null) {
      return DateTime.utc(y, mo, d, h, mi, sec).millisecondsSinceEpoch;
    }
  }
  final hasZone = s.endsWith('Z') || RegExp(r'[+-]\d\d:?\d\d$').hasMatch(s);
  return DateTime.tryParse(hasZone ? s : '${s}Z')?.toUtc().millisecondsSinceEpoch;
}

/// Runs inside an isolate.
Candles parseCandlesFile(String path) {
  final text = _readCsv(path, 'Pick the candle .csv from your downloader (time,open,high,low,close,volume).');
  final lines = const LineSplitter().convert(text);
  if (lines.length < 2) throw const LoadError('The candle file has no rows.');
  final head = _header(lines.first);
  if (head.contains('edge') && head.contains('touch_time')) {
    throw const LoadError('This is an events file. Use Load events for fvg_events.csv, and Load candles for the price file.');
  }
  const need = ['time', 'open', 'high', 'low', 'close'];
  final missing = need.where((c) => !head.contains(c)).toList();
  if (missing.isNotEmpty) {
    throw LoadError('The candle file is missing ${missing.join(', ')}. Expected columns: time,open,high,low,close,volume.');
  }
  final it = head.indexOf('time'), io = head.indexOf('open'), ih = head.indexOf('high');
  final il = head.indexOf('low'), ic = head.indexOf('close'), iv = head.indexOf('volume');
  final maxCol = [it, io, ih, il, ic, iv].reduce(max);

  final cap = lines.length - 1;
  final t = Int64List(cap);
  final o = Float64List(cap), h = Float64List(cap), l = Float64List(cap), c = Float64List(cap), v = Float64List(cap);
  final keys = <String>[];
  var k = 0;
  for (var r = 1; r < lines.length; r++) {
    final line = lines[r];
    if (line.trim().isEmpty) continue;
    final p = line.split(',');
    if (p.length <= maxCol) continue;
    final key = _unq(p[it]);
    final ms = parseUtcMs(key);
    final po = double.tryParse(p[io]), ph = double.tryParse(p[ih]), pl = double.tryParse(p[il]), pc = double.tryParse(p[ic]);
    if (ms == null || po == null || ph == null || pl == null || pc == null) continue;
    if (k > 0 && ms <= t[k - 1]) {
      throw LoadError('Candle times go backwards or repeat at row ${r + 1} ($key). Sort the file by time and drop duplicates.');
    }
    t[k] = ms;
    o[k] = po;
    h[k] = ph;
    l[k] = pl;
    c[k] = pc;
    v[k] = iv < 0 ? 0 : (double.tryParse(p[iv]) ?? 0);
    keys.add(key);
    k++;
  }
  if (k == 0) throw const LoadError('No candle rows could be read. Times should look like 2021-01-03 23:00:00.');

  final diffs = <int>[];
  for (var i = 1; i < k && diffs.length < 5000; i++) {
    diffs.add(t[i] - t[i - 1]);
  }
  diffs.sort();
  final minutes = diffs.isEmpty ? 15 : (diffs[diffs.length ~/ 2] / 60000).round().clamp(1, 1440).toInt();
  return Candles(
    minutes: minutes,
    t: t.sublist(0, k),
    o: o.sublist(0, k),
    h: h.sublist(0, k),
    l: l.sublist(0, k),
    c: c.sublist(0, k),
    v: v.sublist(0, k),
    keys: keys,
  );
}

/// Runs inside an isolate. [companion] files (fvg_fake_events.csv,
/// fvg_control_events.csv) only need time, dir and outcome; the condition
/// columns are used when present so the same filters apply to them.
/// Column names from fvg_conditions.py (form_session, trend, sweep_b, period)
/// are accepted alongside the design's names.
EventsParse parseEventsFile(String path, {bool companion = false}) {
  final name = path.split(RegExp(r'[\\/]')).last;
  final text = _readCsv(path, companion ? 'Expected $name from the study output.' : 'Pick fvg_events.csv from the study output.');
  final lines = const LineSplitter().convert(text);
  if (lines.length < 2) throw LoadError('$name has no rows.');
  final head = _header(lines.first);
  if (head.contains('open') && !head.contains('edge') && !head.contains('outcome')) {
    throw const LoadError('This is a candle file. Use Load candles for it, and Load events for fvg_events.csv.');
  }
  final need = companion
      ? const ['time', 'dir', 'outcome']
      : const ['time', 'touch_time', 'end_time', 'edge', 'far', 'dir', 'gap_atr', 'age', 'max_wick', 'max_close', 'outcome', 'bars', 'scenario', 'size_q'];
  final missing = need.where((c) => !head.contains(c)).toList();
  if (missing.isNotEmpty) {
    throw LoadError('$name is missing ${missing.join(', ')}. Re-export it from the study script.');
  }
  final col = {for (var i = head.length - 1; i >= 0; i--) head[i]: i};
  int? any(List<String> names) {
    for (final n in names) {
      final i = col[n];
      if (i != null) return i;
    }
    return null;
  }

  final iSession = any(const ['formation_session', 'form_session', 'session']);
  final iTouchSession = any(const ['touch_session']);
  final iDisp = any(const ['disp_q', 'displacement', 'disp_bucket']);
  final iTrend = any(const ['htf_trend', 'trend']);
  final iSweep = any(const ['sweep', 'sweep_b', 'swept']);
  final iPeriod = any(const ['period']), iKind = any(const ['kind']);
  final columns = <String>{
    ...head,
    if (iDisp != null) 'disp_q',
    if (iTrend != null) 'htf_trend',
    if (iSweep != null) 'sweep',
  };

  final out = <FvgEvent>[];
  var skipped = 0;
  for (var r = 1; r < lines.length; r++) {
    final line = lines[r];
    if (line.trim().isEmpty) continue;
    final p = _split(line);
    String at(int? i) => i == null || i >= p.length ? '' : p[i];
    String g(String name) => at(col[name]);

    final time = g('time');
    final fm = parseUtcMs(time);
    final touch = g('touch_time').isEmpty && companion ? time : g('touch_time');
    final end = g('end_time').isEmpty && companion ? touch : g('end_time');
    final tm = parseUtcMs(touch), em = parseUtcMs(end);
    double? num(String n, double fallback) => double.tryParse(g(n)) ?? (companion ? fallback : null);
    final edge = num('edge', 0), far = num('far', 0), gapAtr = num('gap_atr', 0);
    final age = num('age', -1), mw = num('max_wick', 0), mc = num('max_close', 0);
    final outcome = parseOutcome(g('outcome'));
    final dir = g('dir').toLowerCase();
    if (fm == null || tm == null || em == null || edge == null || far == null || gapAtr == null || age == null ||
        mw == null || mc == null || outcome == null || (dir != 'bull' && dir != 'bear')) {
      skipped++;
      continue;
    }
    final barsRaw = g('bars');
    out.add(FvgEvent(
      time: time,
      touchTime: touch,
      endTime: end,
      formationMs: fm,
      touchMs: tm,
      endMs: em,
      isBull: dir == 'bull',
      edge: edge,
      far: far,
      gapAtr: gapAtr,
      age: age.round(),
      maxWick: mw,
      maxClose: mc,
      outcome: outcome,
      bars: barsRaw.isEmpty ? null : double.tryParse(barsRaw)?.round(),
      scenario: g('scenario'),
      sizeQ: g('size_q'),
      session: normalizeSession(at(iSession)) ?? sessionForHour(DateTime.fromMillisecondsSinceEpoch(fm, isUtc: true).hour),
      touchSession: normalizeSession(at(iTouchSession)) ?? sessionForHour(DateTime.fromMillisecondsSinceEpoch(tm, isUtc: true).hour),
      dispQ: normalizeDisp(at(iDisp)),
      htfTrend: normalizeTrend(at(iTrend)),
      sweep: parseBool(at(iSweep)),
      period: parsePeriod(at(iPeriod)),
      kind: iKind == null ? null : at(iKind).toLowerCase(),
    ));
  }
  if (out.isEmpty) throw LoadError('No events could be read from $name.');
  out.sort((a, b) => a.formationMs.compareTo(b.formationMs));
  return EventsParse(out, skipped, columns);
}
