import 'dart:io';
import 'dart:typed_data';

import 'candles.dart';
import 'loaders.dart';
import 'resample.dart';

/// Parsing the 2M-row M1 CSV takes a few seconds, so the parsed columns are kept as one raw
/// binary file in the app's cache folder, keyed by the CSV's path, size and mtime.
/// A cache file that doesn't match (or is damaged) is ignored and rewritten. Runs inside an isolate.
Candles loadCandlesCached(String csvPath, String? cacheDir) {
  if (cacheDir == null) return parseCandlesFile(csvPath);
  final src = File(csvPath);
  if (!src.existsSync()) return parseCandlesFile(csvPath); // the parser's own message
  final st = src.statSync();
  final key = '${st.size}_${st.modified.millisecondsSinceEpoch}_${csvPath.hashCode.toUnsigned(32)}';
  final f = File('$cacheDir${Platform.pathSeparator}candles_$key.bin');
  final hit = _read(f, csvPath);
  if (hit != null) return hit;
  final c = parseCandlesFile(csvPath);
  try {
    Directory(cacheDir).createSync(recursive: true);
    // Old caches for this path are dropped so the folder doesn't grow with every new download.
    for (final e in Directory(cacheDir).listSync()) {
      if (e is File && e.path.endsWith('_${csvPath.hashCode.toUnsigned(32)}.bin')) e.deleteSync();
    }
    _write(f, csvPath, c);
  } catch (_) {
    // A cache is a convenience; failing to write one never blocks loading.
  }
  return c;
}

const _magic = 0x484d4331; // "HMC1"

void _write(File f, String path, Candles c) {
  final name = Uint8List.fromList(path.codeUnits.map((u) => u & 0xff).toList());
  final head = ByteData(16)
    ..setUint32(0, _magic)
    ..setUint32(4, c.minutes)
    ..setUint32(8, c.length)
    ..setUint32(12, name.length);
  final tmp = File('${f.path}.tmp');
  final raf = tmp.openSync(mode: FileMode.write);
  raf.writeFromSync(head.buffer.asUint8List());
  raf.writeFromSync(name);
  final pad = (8 - (16 + name.length) % 8) % 8;
  raf.writeFromSync(Uint8List(pad));
  for (final col in [c.t.buffer.asUint8List(c.t.offsetInBytes, c.t.lengthInBytes), for (final d in [c.o, c.h, c.l, c.c, c.v]) d.buffer.asUint8List(d.offsetInBytes, d.lengthInBytes)]) {
    raf.writeFromSync(col);
  }
  raf.closeSync();
  tmp.renameSync(f.path);
}

Candles? _read(File f, String path) {
  try {
    if (!f.existsSync()) return null;
    final b = f.readAsBytesSync();
    if (b.length < 16) return null;
    final head = ByteData.sublistView(b, 0, 16);
    if (head.getUint32(0) != _magic) return null;
    final minutes = head.getUint32(4), n = head.getUint32(8), nl = head.getUint32(12);
    if (String.fromCharCodes(b, 16, 16 + nl) != String.fromCharCodes(path.codeUnits.map((u) => u & 0xff))) return null;
    var off = 16 + nl;
    off += (8 - off % 8) % 8;
    if (b.length != off + n * 8 * 6) return null;
    // Copy into aligned buffers (the byte list's own offset may not be 8-aligned).
    Int64List ints() {
      final r = Int64List(n);
      r.buffer.asUint8List().setRange(0, n * 8, b, off);
      off += n * 8;
      return r;
    }

    Float64List dbl() {
      final r = Float64List(n);
      r.buffer.asUint8List().setRange(0, n * 8, b, off);
      off += n * 8;
      return r;
    }

    return Candles(minutes: minutes, t: ints(), o: dbl(), h: dbl(), l: dbl(), c: dbl(), v: dbl());
  } catch (_) {
    return null;
  }
}

/// The chart series for one run, built inside one isolate so that nothing large is copied
/// between isolates: M1 cut after [lastMs] (the run's last simulated bar), and M5/M15/H1 from it.
Map<String, Candles> runSeries(String csvPath, String? cacheDir, int? lastMs) {
  final m1 = loadCandlesCached(csvPath, cacheDir);
  final cut = lastMs == null ? m1 : m1.head(m1.lowerBound(lastMs + 1));
  final out = <String, Candles>{cut.tf: cut};
  for (final tf in kTimeframes) {
    final m = tfMinutes(tf);
    if (m > cut.minutes && m % cut.minutes == 0) out[tf] = resample(cut, m);
  }
  return out;
}
