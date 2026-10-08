import 'dart:typed_data';

import 'candles.dart';

/// Buckets by UTC time: open first, high max, low min, close last, volume sum.
/// Runs inside an isolate.
Candles resample(Candles src, int minutes) {
  final b = minutes * 60000;
  final t = <int>[], keys = <String>[];
  final o = <double>[], h = <double>[], l = <double>[], c = <double>[], v = <double>[];
  var cur = -1 << 62;
  for (var i = 0; i < src.length; i++) {
    final k = src.t[i] - src.t[i] % b;
    if (k != cur) {
      cur = k;
      t.add(k);
      keys.add(formatKey(k));
      o.add(src.o[i]);
      h.add(src.h[i]);
      l.add(src.l[i]);
      c.add(src.c[i]);
      v.add(src.v[i]);
    } else {
      final j = t.length - 1;
      if (src.h[i] > h[j]) h[j] = src.h[i];
      if (src.l[i] < l[j]) l[j] = src.l[i];
      c[j] = src.c[i];
      v[j] += src.v[i];
    }
  }
  return Candles(
    minutes: minutes,
    t: Int64List.fromList(t),
    o: Float64List.fromList(o),
    h: Float64List.fromList(h),
    l: Float64List.fromList(l),
    c: Float64List.fromList(c),
    v: Float64List.fromList(v),
    keys: keys,
  );
}
