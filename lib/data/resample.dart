import 'dart:typed_data';

import 'candles.dart';

/// Buckets by UTC time: open first, high max, low min, close last, volume sum.
/// M5/M15/H1 are UTC-aligned in the engine too (SPEC §7.3). Runs inside an isolate.
Candles resample(Candles src, int minutes) {
  final b = minutes * 60000, n = src.length;
  // At most one output bar per input bar; trimmed at the end.
  final t = Int64List(n);
  final o = Float64List(n), h = Float64List(n), l = Float64List(n), c = Float64List(n), v = Float64List(n);
  var j = -1, cur = -1 << 62;
  for (var i = 0; i < n; i++) {
    final k = src.t[i] - src.t[i] % b;
    if (k != cur) {
      cur = k;
      j++;
      t[j] = k;
      o[j] = src.o[i];
      h[j] = src.h[i];
      l[j] = src.l[i];
      c[j] = src.c[i];
      v[j] = src.v[i];
    } else {
      if (src.h[i] > h[j]) h[j] = src.h[i];
      if (src.l[i] < l[j]) l[j] = src.l[i];
      c[j] = src.c[i];
      v[j] += src.v[i];
    }
  }
  final m = j + 1;
  return Candles(
    minutes: minutes,
    t: t.sublist(0, m),
    o: o.sublist(0, m),
    h: h.sublist(0, m),
    l: l.sublist(0, m),
    c: c.sublist(0, m),
    v: v.sublist(0, m),
  );
}
