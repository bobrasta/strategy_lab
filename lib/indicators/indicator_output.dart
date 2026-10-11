import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../run/equity_store.dart' show forEachLine;
import '../run/run_data.dart';
import '../run/run_view.dart';
import '../util/fastparse.dart';

/// Shown to the user as-is.
class IndicatorLoadError implements Exception {
  const IndicatorLoadError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// One declared plot (MT5 `indicator_plots`, DRAW_LINE): SPEC §7.7 `PLOT_LINE`.
class PlotSpec {
  const PlotSpec({required this.index, required this.name, required this.label, required this.color, required this.style, required this.width});

  factory PlotSpec.fromJson(Map j, int fallbackIndex) => PlotSpec(
    index: (j['index'] as num?)?.toInt() ?? fallbackIndex,
    name: '${j['name'] ?? 'Plot$fallbackIndex'}',
    label: '${j['label'] ?? j['name'] ?? ''}',
    color: '${j['color'] ?? 'mute'}',
    style: '${j['style'] ?? 'solid'}',
    width: (j['width'] as num?)?.toDouble() ?? 1,
  );

  final int index;
  final String name, label, color, style;
  final double width;
  bool get dashed => style == 'dashed';
}

/// Every `Set` of one plot (plots.csv), sorted by bar time and, within a bar time, in emission
/// order (= stamp order). A bar set again later (repainting) has several records; which one is
/// shown depends on "now" (SPEC §7.7 display rule). `value` NaN = EMPTY_VALUE (a gap).
class PlotSeries {
  PlotSeries(this.time, this.stamp, this.value);
  final Int64List time, stamp;
  final Float64List value;

  int get length => time.length;

  /// First record with time >= [ms].
  int lowerBound(int ms) {
    var lo = 0, hi = time.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (time[mid] < ms) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// The record shown for the bar time of record [i]'s group at [now]: the last record of that
  /// group with stamp ≤ now, or -1. [end] is the group's end (exclusive).
  int _pick(int start, int end, int now) {
    var k = -1;
    for (var j = start; j < end && stamp[j] <= now; j++) {
      k = j;
    }
    return k;
  }

  int _groupEnd(int i) {
    final t = time[i];
    var j = i + 1;
    while (j < time.length && time[j] == t) {
      j++;
    }
    return j;
  }

  /// The value at bar time [ms] as known at [now] (NaN = EMPTY_VALUE), or null when no record
  /// for that bar is stamped at or before now.
  double? valueAt(int ms, int now) {
    final i = lowerBound(ms);
    if (i >= time.length || time[i] != ms) return null;
    final k = _pick(i, _groupEnd(i), now);
    return k < 0 ? null : value[k];
  }

  /// The record indexes shown at [now] for bar times in [from, to], in time order, plus one
  /// shown record either side so a line enters and leaves the view. Never a record stamped after
  /// [now]; a bar time with no record stamped by then has no point.
  Iterable<int> visible(int from, int to, int now) sync* {
    final i0 = lowerBound(from);
    // The last shown record before `from` (a few groups back at most: older bars are known).
    for (var j = i0 - 1, groups = 0; j >= 0 && groups < 64; groups++) {
      var s = j;
      while (s > 0 && time[s - 1] == time[j]) {
        s--;
      }
      final k = _pick(s, j + 1, now);
      if (k >= 0) {
        yield k;
        break;
      }
      j = s - 1;
    }
    // A record's bar time is ≤ its stamp, so nothing after `now` can be shown.
    for (var i = i0; i < time.length && time[i] <= now;) {
      final end = _groupEnd(i);
      final k = _pick(i, end, now);
      if (k >= 0) {
        yield k;
        if (time[i] > to) break; // the one point right of the view
      }
      i = end;
    }
  }
}

/// Indicator objects (drawings.jsonl, SPEC §7.4), stored compactly: an FVG indicator over six
/// years can write hundreds of thousands of events, too many to keep one map per event.
/// Each object "life" (create → re-create or delete) keeps its versions in stamp order: the
/// object's state right after each of its events, folded with the same rules as a run's drawings
/// ([createDrawObj], [moveDrawObj]). The state at "now" is the last version stamped at or before it.
class DrawingIndex {
  DrawingIndex._({
    required this.strings,
    required this.evStamp,
    required this.evT1,
    required this.evT2,
    required this.evP1,
    required this.evP2,
    required this.evNext,
    required this.lifeName,
    required this.lifeKind,
    required this.lifeColor,
    required this.lifeLabel,
    required this.lifeShape,
    required this.lifeCreate,
    required this.lifeDelete,
    required this.lifeFirst,
    required this.lifeMinT1,
    required this.lifeMaxEnd,
    required this.events,
  }) : _blockMaxEnd = _blocks(lifeMaxEnd);

  static const _kBlock = 64;

  /// The latest end of any life in each block of 64: closed history is skipped a block at a time.
  final Int64List _blockMaxEnd;

  static Int64List _blocks(Int64List maxEnd) {
    final out = Int64List((maxEnd.length + _kBlock - 1) ~/ _kBlock);
    for (var b = 0; b < out.length; b++) {
      var m = -kOpenEnd;
      for (var i = b * _kBlock; i < maxEnd.length && i < (b + 1) * _kBlock; i++) {
        if (maxEnd[i] > m) m = maxEnd[i];
      }
      out[b] = m;
    }
    return out;
  }

  /// t2 of an open-ended version (OPEN_END: extends to "now"); also "never deleted".
  static const kOpenEnd = 0x7fffffffffffffff;

  final List<String> strings;

  /// Per version: its stamp and the folded geometry (t2 = [kOpenEnd] when open-ended).
  final Int64List evStamp, evT1, evT2;
  final Float64List evP1, evP2;

  /// The life's next version, or -1.
  final Int32List evNext;
  final Int32List lifeName, lifeKind, lifeColor, lifeLabel, lifeShape, lifeFirst;

  /// Creation and deletion stamps ([kOpenEnd] = never deleted); the extent over all versions.
  final Int64List lifeCreate, lifeDelete, lifeMinT1, lifeMaxEnd;

  /// drawings.jsonl lines read (create, move and delete events).
  final int events;

  int get lives => lifeCreate.length;

  static final empty = DrawingIndexBuilder().build();

  /// Objects as of [now] whose span meets [from, to] (bar times; open-ended ones reach now).
  /// Only events stamped at or before [now] count.
  List<DrawObj> objectsAt(int now, int from, int to) {
    if (now == _mNow && from == _mFrom && to == _mTo) return _memo;
    // Lives are in creation (= stamp) order.
    var lo = 0, hi = lifeCreate.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (lifeCreate[mid] <= now) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    final out = <DrawObj>[];
    for (var i = 0; i < lo; i++) {
      if (i % _kBlock == 0 && _blockMaxEnd[i ~/ _kBlock] < from) {
        i += _kBlock - 1;
        continue;
      }
      if (lifeDelete[i] <= now || lifeMinT1[i] > to || lifeMaxEnd[i] < from) continue;
      var e = lifeFirst[i];
      for (var n = evNext[e]; n >= 0 && evStamp[n] <= now; n = evNext[n]) {
        e = n;
      }
      final t1 = evT1[e], t2 = evT2[e];
      final end = strings[lifeKind[i]] == 'marker' ? t1 : (t2 == kOpenEnd ? now : t2);
      if (t1 > to || end < from) continue;
      out.add(
        createDrawObj(strings[lifeName[i]], strings[lifeKind[i]], strings[lifeColor[i]], strings[lifeLabel[i]], lifeShape[i] < 0 ? null : strings[lifeShape[i]])
          ..t1 = t1
          ..p1 = evP1[e]
          ..t2 = t2 == kOpenEnd ? null : t2
          ..p2 = evP2[e],
      );
    }
    _mNow = now;
    _mFrom = from;
    _mTo = to;
    return _memo = out;
  }

  // The painter asks twice per frame (below and above the candles), and hover repaints often.
  int _mNow = 0, _mFrom = 0, _mTo = -1;
  List<DrawObj> _memo = const [];
}

/// Builds a [DrawingIndex] from drawings.jsonl events in file order.
class DrawingIndexBuilder {
  final _strings = <String>[], _ids = <String, int>{};
  final _stamp = <int>[], _t1 = <int>[], _t2 = <int>[], _next = <int>[];
  final _p1 = <double>[], _p2 = <double>[];
  final _name = <int>[], _kind = <int>[], _color = <int>[], _label = <int>[], _shape = <int>[];
  final _create = <int>[], _delete = <int>[], _first = <int>[], _lastEv = <int>[], _minT1 = <int>[], _maxEnd = <int>[];

  /// The live object of each name, folded so far (the run drawings' rules).
  final _live = <String, (int, DrawObj)>{};
  int _events = 0;

  int _id(String s) => _ids.putIfAbsent(s, () {
    _strings.add(s);
    return _strings.length - 1;
  });

  void add(DrawEvent e) {
    _events++;
    final j = e.j, name = e.name;
    switch (e.op) {
      case 'delete':
        final l = _live.remove(name);
        if (l != null) _delete[l.$1] = e.ms;
        return;
      case 'create':
        final old = _live[name];
        if (old != null) _delete[old.$1] = e.ms; // a re-create replaces the object
        final o = createDrawObj(name, j['kind'], j['color'], j['label'], j['shape']);
        _name.add(_id(o.name));
        _kind.add(_id(o.kind));
        _color.add(_id(o.color));
        _label.add(_id(o.label));
        _shape.add(o.shape == null ? -1 : _id(o.shape!));
        _create.add(e.ms);
        _delete.add(DrawingIndex.kOpenEnd);
        _first.add(-1);
        _lastEv.add(-1);
        _minT1.add(DrawingIndex.kOpenEnd);
        _maxEnd.add(-DrawingIndex.kOpenEnd);
        _live[name] = (_create.length - 1, o);
    }
    final live = _live[name];
    if (live == null) return; // a move of an object that doesn't exist (as in a run's drawings)
    final (l, o) = live;
    moveDrawObj(o, t1: engineMs(j['t1']), p1: (j['p1'] as num?)?.toDouble(), hasT2: j.containsKey('t2'), t2: engineMs(j['t2']), p2: (j['p2'] as num?)?.toDouble());
    final ev = _stamp.length;
    _stamp.add(e.ms);
    _t1.add(o.t1);
    _t2.add(o.t2 ?? DrawingIndex.kOpenEnd);
    _p1.add(o.p1);
    _p2.add(o.p2);
    _next.add(-1);
    if (_lastEv[l] < 0) {
      _first[l] = ev;
    } else {
      _next[_lastEv[l]] = ev;
    }
    _lastEv[l] = ev;
    if (o.t1 < _minT1[l]) _minT1[l] = o.t1;
  }

  /// The latest end each life can show: an open-ended version reaches "now", which is before the
  /// next version's stamp (or the delete) while it is the current one.
  void _ends() {
    for (var l = 0; l < _create.length; l++) {
      final marker = _strings[_kind[l]] == 'marker';
      var m = -DrawingIndex.kOpenEnd;
      for (var e = _first[l]; e >= 0; e = _next[e]) {
        final n = _next[e];
        final end = marker ? _t1[e] : (_t2[e] != DrawingIndex.kOpenEnd ? _t2[e] : (n >= 0 ? _stamp[n] : _delete[l]));
        if (end > m) m = end;
      }
      _maxEnd[l] = m;
    }
  }

  DrawingIndex build() {
    _ends();
    return DrawingIndex._(
      strings: List.unmodifiable(_strings),
      evStamp: Int64List.fromList(_stamp),
      evT1: Int64List.fromList(_t1),
      evT2: Int64List.fromList(_t2),
      evP1: Float64List.fromList(_p1),
      evP2: Float64List.fromList(_p2),
      evNext: Int32List.fromList(_next),
      lifeName: Int32List.fromList(_name),
      lifeKind: Int32List.fromList(_kind),
      lifeColor: Int32List.fromList(_color),
      lifeLabel: Int32List.fromList(_label),
      lifeShape: Int32List.fromList(_shape),
      lifeCreate: Int64List.fromList(_create),
      lifeDelete: Int64List.fromList(_delete),
      lifeFirst: Int32List.fromList(_first),
      lifeMinT1: Int64List.fromList(_minT1),
      lifeMaxEnd: Int64List.fromList(_maxEnd),
      events: _events,
    );
  }
}

/// A finished indicator output folder (SPEC §7.7): indicator.json, plots.csv, drawings.jsonl,
/// journal.txt. Every value comes from these files.
class IndicatorOutput {
  IndicatorOutput({required this.dir, required this.manifest, required this.plots, required this.series, required this.drawings, required this.journal, required this.plotRecords});

  final String dir;
  final Map<String, dynamic> manifest;
  final List<PlotSpec> plots;

  /// Records per plot index (a plot without records has none here).
  final Map<int, PlotSeries> series;
  final DrawingIndex drawings;
  final List<JournalLine> journal;

  /// plots.csv rows read.
  final int plotRecords;

  List<String> get warnings => [for (final w in (manifest['warnings'] as List?) ?? const []) '$w'];
}

class _PlotBuilder {
  var time = Int64List(1024), stamp = Int64List(1024);
  var value = Float64List(1024);
  int n = 0;
  bool sorted = true;

  void add(int s, int t, double v) {
    if (n == time.length) {
      time = (Int64List(n * 2)..setRange(0, n, time));
      stamp = (Int64List(n * 2)..setRange(0, n, stamp));
      value = (Float64List(n * 2)..setRange(0, n, value));
    }
    if (n > 0 && t < time[n - 1]) sorted = false;
    time[n] = t;
    stamp[n] = s;
    value[n] = v;
    n++;
  }

  PlotSeries build() {
    if (sorted) {
      return PlotSeries(Int64List.sublistView(time, 0, n), Int64List.sublistView(stamp, 0, n), Float64List.sublistView(value, 0, n));
    }
    // Repainted bars came later in the file: order by bar time, keeping emission (stamp) order
    // within a bar time.
    final idx = List<int>.generate(n, (i) => i)..sort((a, b) => time[a] != time[b] ? time[a].compareTo(time[b]) : a.compareTo(b));
    final t = Int64List(n), s = Int64List(n), v = Float64List(n);
    for (var i = 0; i < n; i++) {
      t[i] = time[idx[i]];
      s[i] = stamp[idx[i]];
      v[i] = value[idx[i]];
    }
    return PlotSeries(t, s, v);
  }
}

/// plots.csv: `stamp,plot,time,value` (times `YYYY-MM-DD HH:MM:SS` UTC; empty value =
/// EMPTY_VALUE). A header line, blank lines and malformed lines (a truncated file) are skipped.
(Map<int, PlotSeries>, int) parsePlotsCsv(String path) {
  final f = File(path);
  if (!f.existsSync()) return (const {}, 0);
  final builders = <int, _PlotBuilder>{};
  final line = CsvLine(8);
  var rows = 0;
  final raf = f.openSync();
  try {
    forEachLine(raf, 0, raf.lengthSync(), (b, s, e, _) {
      line.split(b, s, e);
      if (line.count < 4) return;
      final st = parseTimeBytes(b, line.start(0), line.end(0));
      final t = parseTimeBytes(b, line.start(2), line.end(2));
      if (st == null || t == null) return; // header or damaged line
      var p = 0;
      final ps = line.start(1), pe = line.end(1);
      if (ps >= pe) return;
      for (var i = ps; i < pe; i++) {
        final c = b[i];
        if (c < 48 || c > 57) return;
        p = p * 10 + c - 48;
      }
      final vs = line.start(3), ve = line.end(3);
      double v;
      if (vs >= ve) {
        v = double.nan;
      } else {
        final x = parseDoubleBytes(b, vs, ve);
        if (x == null) return;
        // EMPTY_VALUE written as a number (MT5's DBL_MAX) is a gap too.
        v = x.isFinite && x.abs() < 1e300 ? x : double.nan;
      }
      builders.putIfAbsent(p, _PlotBuilder.new).add(st, t, v);
      rows++;
    });
  } finally {
    raf.closeSync();
  }
  return ({for (final e in builders.entries) e.key: e.value.build()}, rows);
}

/// drawings.jsonl (same format as a run's), read line by line into a [DrawingIndex].
DrawingIndex parseIndicatorDrawings(String path) {
  final f = File(path);
  if (!f.existsSync()) return DrawingIndex.empty;
  final b = DrawingIndexBuilder();
  final raf = f.openSync();
  try {
    forEachLine(raf, 0, raf.lengthSync(), (bytes, s, e, _) {
      final ev = parseDrawLine(utf8.decode(Uint8List.sublistView(bytes, s, e), allowMalformed: true));
      if (ev != null) b.add(ev);
    });
  } finally {
    raf.closeSync();
  }
  return b.build();
}

/// Loads a finished indicator output folder. Runs inside an isolate (large files).
/// [declared] are the plots from `indicator_inputs`, used when indicator.json lists none.
IndicatorOutput loadIndicatorOutput(String dir, {List<PlotSpec> declared = const []}) {
  final mf = File(joinPath(dir, 'indicator.json'));
  if (!mf.existsSync()) throw IndicatorLoadError('No indicator.json in $dir. The indicator may have been stopped before it finished.');
  Map<String, dynamic> manifest;
  try {
    final j = jsonDecode(mf.readAsStringSync());
    if (j is! Map) throw const FormatException('not an object');
    manifest = j.cast<String, dynamic>();
  } on FormatException catch (e) {
    throw IndicatorLoadError("indicator.json in ${baseName(dir)} couldn't be read: ${e.message}");
  }
  final pj = manifest['plots'];
  final plots = pj is List && pj.isNotEmpty
      ? [
          for (var i = 0; i < pj.length; i++)
            if (pj[i] is Map) PlotSpec.fromJson(pj[i] as Map, i),
        ]
      : declared;
  final (series, rows) = parsePlotsCsv(joinPath(dir, 'plots.csv'));
  final drawings = parseIndicatorDrawings(joinPath(dir, 'drawings.jsonl'));
  final jf = File(joinPath(dir, 'journal.txt'));
  final journal = jf.existsSync() ? parseJournal(jf.readAsStringSync()) : const <JournalLine>[];
  return IndicatorOutput(dir: dir, manifest: manifest, plots: plots, series: series, drawings: drawings, journal: journal, plotRecords: rows);
}
