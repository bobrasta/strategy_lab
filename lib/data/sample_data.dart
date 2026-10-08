import 'dart:math';
import 'dart:typed_data';

import 'candles.dart';

/// Waypoints (bar index, price) for a deterministic XAUUSD M15 demo series.
const List<List<double>> _wp = [
  [0, 2338], [10, 2335], [18, 2331], [19, 2331.5], [20, 2345], [21, 2348], [30, 2352], [38, 2341.5],
  [48, 2361], [56, 2358], [63, 2366], [64, 2353], [65, 2350], [74, 2356], [80, 2362.5], [86, 2370],
  [96, 2374], [99, 2372.5], [100, 2386], [101, 2389], [106, 2391], [112, 2381], [122, 2402], [128, 2398],
  [133, 2394.5], [134, 2406], [135, 2408], [140, 2405], [145, 2399], [152, 2390], [158, 2392.5], [159, 2380],
  [160, 2377], [166, 2381], [170, 2384], [176, 2385], [184, 2372], [192, 2364], [196, 2368], [201, 2366],
  [202, 2379], [203, 2382], [208, 2384], [212, 2374], [222, 2362], [228, 2364], [229, 2365], [230, 2353],
  [231, 2350], [235, 2352], [239, 2356],
];

/// Demo candles for the presets. Not market data.
Candles generateSampleCandles({int count = 240, int seed = 11}) {
  final r = Random(seed);
  double g() {
    final u = max(r.nextDouble(), 1e-9), v = r.nextDouble();
    return sqrt(-2 * log(u)) * cos(2 * pi * v);
  }

  double path(int i) {
    for (var k = 1; k < _wp.length; k++) {
      final a = _wp[k - 1], b = _wp[k];
      if (i <= b[0]) return a[1] + (b[1] - a[1]) * (i - a[0]) / (b[0] - a[0]);
    }
    return _wp.last[1];
  }

  final t0 = DateTime.utc(2025, 3, 11, 8).millisecondsSinceEpoch;
  final t = Int64List(count);
  final o = Float64List(count), h = Float64List(count), l = Float64List(count), c = Float64List(count), v = Float64List(count);
  final keys = <String>[];
  double noise = 0;
  double? prev;
  for (var i = 0; i < count; i++) {
    noise = 0.6 * noise + 0.5 * g();
    final close = path(i) + noise, open = prev ?? close - 0.4;
    t[i] = t0 + i * 15 * 60000;
    o[i] = open;
    c[i] = close;
    h[i] = max(open, close) + 0.45 + g().abs() * 0.8;
    l[i] = min(open, close) - 0.45 - g().abs() * 0.8;
    v[i] = 100 + r.nextDouble() * 50;
    keys.add(formatKey(t[i]));
    prev = close;
  }
  return Candles(minutes: 15, t: t, o: o, h: h, l: l, c: c, v: v, keys: keys);
}
