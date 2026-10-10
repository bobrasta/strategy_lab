import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import '../util/fastparse.dart';
import 'run_data.dart' show RunLoadError;

/// One equity.csv row, exactly as the engine wrote it. [profit]/[drawdown]/[drawdownPct] are null
/// for runs written before those columns existed.
class EquityRow {
  const EquityRow(this.ms, this.deal, this.balance, this.equity, this.equityMin, this.margin, this.profit, this.drawdown, this.drawdownPct);
  final int ms;
  final bool deal;
  final double balance, equity, equityMin, margin;
  final double? profit, drawdown, drawdownPct;
}

/// What one pass over equity.csv yields: a sparse row index for random access, and a
/// downsampled series for the graph. Plain typed data, so it crosses isolates cheaply.
class EquityIndex {
  EquityIndex({
    required this.fileLen,
    required this.rows,
    required this.columns,
    required this.blockMs,
    required this.blockOff,
    required this.gMs,
    required this.gFirstMs,
    required this.gBalance,
    required this.gEquity,
    required this.gEqMin,
    required this.gEqMax,
    required this.gDd,
    required this.gDdPct,
  });

  static const blockRows = 512;

  final int fileLen, rows;
  final List<String> columns;

  /// Time and byte offset of every [blockRows]th row.
  final Int64List blockMs, blockOff;

  /// Graph buckets of consecutive rows: the last row's time, balance and equity; the lowest
  /// equity_min and highest equity in the bucket; the deepest drawdown (money, %) in the bucket.
  /// Values are picked from rows (min/max), never computed, and parsed to plotting precision:
  /// text readouts use exact rows from [EquityStore.at]. [gFirstMs] is the bucket's first row time.
  final Int64List gMs, gFirstMs;
  final Float64List gBalance, gEquity, gEqMin, gEqMax, gDd, gDdPct;

  bool get hasDrawdown => columns.contains('drawdown_pct');
  bool get hasProfit => columns.contains('profit');
  int get firstMs => blockMs.isEmpty ? 0 : blockMs.first;
  int get lastMs => gMs.isEmpty ? 0 : gMs.last;
  int get buckets => gMs.length;
}

class _Cols {
  _Cols(List<String> h)
      : time = h.indexOf('time'),
        kind = h.indexOf('kind'),
        balance = h.indexOf('balance'),
        equity = h.indexOf('equity'),
        equityMin = h.indexOf('equity_min'),
        margin = h.indexOf('margin'),
        profit = h.indexOf('profit'),
        drawdown = h.indexOf('drawdown'),
        drawdownPct = h.indexOf('drawdown_pct');
  final int time, kind, balance, equity, equityMin, margin, profit, drawdown, drawdownPct;
  int get count => [time, kind, balance, equity, equityMin, margin, profit, drawdown, drawdownPct].reduce(max) + 1;
}

EquityRow? _row(Uint8List b, int s, int e, _Cols c, CsvLine f) {
  f.split(b, s, e);
  if (f.count < c.count) return null;
  double? num(int col) => col < 0 ? null : parseDoubleBytes(b, f.start(col), f.end(col));
  final ms = parseTimeBytes(b, f.start(c.time), f.end(c.time));
  final bal = num(c.balance), eq = num(c.equity), mn = num(c.equityMin), mg = num(c.margin);
  if (ms == null || bal == null || eq == null || mn == null || mg == null) return null;
  final deal = c.kind >= 0 && f.end(c.kind) > f.start(c.kind) && b[f.start(c.kind)] == 100; // 'd'
  return EquityRow(ms, deal, bal, eq, mn, mg, num(c.profit), num(c.drawdown), num(c.drawdownPct));
}

/// One sequential pass over equity.csv in 8 MB chunks (never the whole ~290 MB file in memory).
/// Runs inside an isolate.
EquityIndex scanEquityFile(String path, {int targetBuckets = 3000}) {
  final f = File(path);
  if (!f.existsSync()) throw RunLoadError('equity.csv is missing (${f.path}).');
  final raf = f.openSync();
  try {
    final len = raf.lengthSync();
    const chunk = 8 << 20;
    var buf = Uint8List(chunk + 4096);
    var have = 0, off = 0; // bytes in buf; file offset of buf[0]
    bool fill() {
      if (off + have >= len) return false;
      if (buf.length - have < chunk) {
        final nb = Uint8List(have + chunk + 4096);
        nb.setRange(0, have, buf);
        buf = nb;
      }
      have += raf.readIntoSync(buf, have, have + min(chunk, buf.length - have));
      return true;
    }

    fill();
    var nl = buf.indexOf(10);
    if (nl < 0 || nl > have) throw RunLoadError('equity.csv has no header line.');
    final header = String.fromCharCodes(buf, 0, nl).trim().split(',');
    final cols = _Cols(header);
    if (cols.time < 0 || cols.balance < 0 || cols.equity < 0 || cols.equityMin < 0 || cols.margin < 0) {
      throw RunLoadError('equity.csv has unexpected columns: ${header.join(',')}');
    }
    // Rows per graph bucket, from the average row length of the first chunk.
    var sampleRows = 0;
    for (var i = nl + 1; i < have; i++) {
      if (buf[i] == 10) sampleRows++;
    }
    final avg = sampleRows == 0 ? 80.0 : (have - nl) / sampleRows;
    final perBucket = max(1, (len / avg / targetBuckets).ceil());

    final sc = _Scan(cols, header.length, perBucket);
    var ls = nl + 1;
    while (true) {
      for (var i = ls; i < have; i++) {
        if (buf[i] == 10) {
          if (i > ls) sc.take(buf, ls, i, off);
          ls = i + 1;
        }
      }
      // keep the partial line, refill
      final rest = have - ls;
      buf.setRange(0, rest, buf, ls);
      off += ls;
      have = rest;
      ls = 0;
      if (!fill()) {
        if (have > 0) sc.take(buf, 0, have, off);
        break;
      }
    }
    return EquityIndex(
      fileLen: len,
      rows: sc.rows,
      columns: header,
      blockMs: Int64List.fromList(sc.bMs),
      blockOff: Int64List.fromList(sc.bOff),
      gMs: Int64List.fromList(sc.gMs),
      gFirstMs: Int64List.fromList(sc.gFirst),
      gBalance: Float64List.fromList(sc.gBal),
      gEquity: Float64List.fromList(sc.gEq),
      gEqMin: Float64List.fromList(sc.gMin),
      gEqMax: Float64List.fromList(sc.gMax),
      gDd: Float64List.fromList(sc.gDd),
      gDdPct: Float64List.fromList(sc.gDdp),
    );
  } finally {
    raf.closeSync();
  }
}

/// Graph values only need to land on the right pixel, so the scan uses [parseDoubleApprox]; rows
/// whose numbers are shown as text are read exactly by [EquityStore.at].
class _Scan {
  _Scan(this.cols, int nCols, this.perBucket) : line = CsvLine(nCols + 2);
  final _Cols cols;
  final int perBucket;
  final CsvLine line;
  int rows = 0, inBucket = 0;
  final bMs = <int>[], bOff = <int>[], gMs = <int>[], gFirst = <int>[];
  final gBal = <double>[], gEq = <double>[], gMin = <double>[], gMax = <double>[], gDd = <double>[], gDdp = <double>[];

  double _num(Uint8List b, int col) => col < 0 ? 0 : (parseDoubleApprox(b, line.start(col), line.end(col)) ?? 0);

  void take(Uint8List b, int s, int e, int off) {
    line.split(b, s, e);
    if (line.count < cols.count) return;
    final ms = parseTimeBytes(b, line.start(cols.time), line.end(cols.time));
    if (ms == null) return;
    final bal = _num(b, cols.balance), eq = _num(b, cols.equity), mn = _num(b, cols.equityMin);
    final dd = _num(b, cols.drawdown), ddp = _num(b, cols.drawdownPct);
    if (rows % EquityIndex.blockRows == 0) {
      bMs.add(ms);
      bOff.add(off + s);
    }
    rows++;
    if (inBucket == 0) {
      gFirst.add(ms);
      gMs.add(ms);
      gBal.add(bal);
      gEq.add(eq);
      gMin.add(mn);
      gMax.add(eq);
      gDd.add(dd);
      gDdp.add(ddp);
    } else {
      final j = gMs.length - 1;
      gMs[j] = ms;
      gBal[j] = bal;
      gEq[j] = eq;
      if (mn < gMin[j]) gMin[j] = mn;
      if (eq > gMax[j]) gMax[j] = eq;
      if (dd > gDd[j]) gDd[j] = dd;
      if (ddp > gDdp[j]) gDdp[j] = ddp;
    }
    inBucket = inBucket + 1 == perBucket ? 0 : inBucket + 1;
  }
}

/// equity.csv of one run: the index from one background scan, plus exact rows read on demand
/// (one [EquityIndex.blockRows]-row block from disk, ~50 KB) for replay readouts at the cursor.
class EquityStore {
  EquityStore(this.path, this.index);

  final String path;
  final EquityIndex index;
  RandomAccessFile? _raf;
  final _cache = <int, List<EquityRow>>{}; // LRU by insertion order
  _Cols? _cols;

  static Future<EquityStore> open(String path) async => EquityStore(path, await Isolate.run(() => scanEquityFile(path)));

  int _blockFor(int ms) {
    var lo = 0, hi = index.blockMs.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (index.blockMs[mid] <= ms) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo - 1;
  }

  List<EquityRow> _block(int b) {
    final hit = _cache.remove(b);
    if (hit != null) return _cache[b] = hit;
    final raf = _raf ??= File(path).openSync();
    final s = index.blockOff[b], e = b + 1 < index.blockOff.length ? index.blockOff[b + 1] : index.fileLen;
    raf.setPositionSync(s);
    final bytes = raf.readSync(e - s);
    final cols = _cols ??= _Cols(index.columns);
    final fields = CsvLine(index.columns.length + 2);
    final rows = <EquityRow>[];
    var ls = 0;
    for (var i = 0; i <= bytes.length; i++) {
      if (i == bytes.length || bytes[i] == 10) {
        if (i > ls) {
          final r = _row(bytes, ls, i, cols, fields);
          if (r != null) rows.add(r);
        }
        ls = i + 1;
      }
    }
    if (_cache.length >= 8) _cache.remove(_cache.keys.first);
    return _cache[b] = rows;
  }

  /// The last row stamped at or before [ms] (never a later one), or null before the first row.
  EquityRow? at(int ms) {
    final b = _blockFor(ms);
    if (b < 0) return null;
    final rows = _block(b);
    EquityRow? best;
    for (final r in rows) {
      if (r.ms > ms) break;
      best = r;
    }
    return best;
  }

  void close() {
    _raf?.closeSync();
    _raf = null;
    _cache.clear();
  }
}
