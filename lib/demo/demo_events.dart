// ─────────────────────────────────────────────────────────────────────────────
// DEMO ONLY. Not a study engine.
//
// Builds an fvg_events.csv-shaped list for the bundled sample candles so the
// demo presets (--dart-define=PRESET=1..4) have zones to show. It is never used
// for loaded files: once you load your own candles or events, the app reads
// outcomes exclusively from the Python study's fvg_events.csv.
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:math';

import '../data/candles.dart';
import '../data/events.dart';

List<FvgEvent> demoEvents(Candles c, {double k = 1.0, double buffer = 0.25, int maxBars = 96}) {
  final n = c.length;
  if (n < 3) return [];
  final ranges = [for (var i = 0; i < n; i++) c.h[i] - c.l[i]]..sort();
  final atr = ranges[n ~/ 2];
  final found = <({int i, bool bull, double edge, double far, int touch, int end, EvOutcome out, double mw, double mc})>[];
  var last = -10;
  for (var i = 1; i < n - 1; i++) {
    if (i - last <= 2) continue;
    bool? bull;
    double edge = 0, far = 0;
    if (c.l[i + 1] - c.h[i - 1] >= 0.5 * atr) {
      bull = true;
      edge = c.l[i + 1];
      far = c.h[i - 1];
    } else if (c.l[i - 1] - c.h[i + 1] >= 0.5 * atr) {
      bull = false;
      edge = c.h[i + 1];
      far = c.l[i - 1];
    }
    if (bull == null) continue;
    last = i;
    final gap = (edge - far).abs();
    int? touch;
    for (var j = i + 2; j < n; j++) {
      if (bull ? c.l[j] <= edge : c.h[j] >= edge) {
        touch = j;
        break;
      }
    }
    if (touch == null) continue;
    final target = bull ? edge + k * gap : edge - k * gap, fail = bull ? far - buffer * gap : far + buffer * gap;
    double mw = 0, mc = 0;
    var end = n - 1;
    var out = EvOutcome.timeout;
    for (var j = touch; j < n; j++) {
      mw = max(mw, bull ? (edge - c.l[j]) / gap : (c.h[j] - edge) / gap);
      mc = max(mc, bull ? (edge - c.c[j]) / gap : (c.c[j] - edge) / gap);
      if (bull ? c.c[j] < fail : c.c[j] > fail) {
        end = j;
        out = EvOutcome.through;
        break;
      }
      if (j > touch && (bull ? c.h[j] >= target : c.l[j] <= target)) {
        end = j;
        out = EvOutcome.bounce;
        break;
      }
      if (j - touch >= maxBars) {
        end = j;
        break;
      }
    }
    found.add((i: i, bull: bull, edge: edge, far: far, touch: touch, end: end, out: out, mw: mw, mc: mc));
  }

  final sizes = found.map((f) => (f.edge - f.far).abs() / atr).toList()..sort();
  final disps = found.map((f) => (c.c[f.i] - c.o[f.i]).abs() / atr).toList()..sort();
  String quart(List<double> sorted, double v, List<String> labels) {
    if (sorted.isEmpty) return labels[1];
    final q = sorted.where((s) => s <= v).length / sorted.length;
    return q <= 0.25 ? labels[0] : q <= 0.5 ? labels[1] : q <= 0.75 ? labels[2] : labels[3];
  }

  String sizeQ(double v) => quart(sizes, v, const ['Q1 small', 'Q2', 'Q3', 'Q4 big']);
  String trend(int i, bool bull) {
    final back = max(0, i - 32);
    final up = c.c[i] >= c.c[back];
    return up == bull ? 'Aligned' : 'Against';
  }

  bool sweep(int i, bool bull) {
    final from = max(0, i - 12), to = i - 2;
    if (to <= from) return false;
    var ext = bull ? double.infinity : -double.infinity;
    for (var j = from; j <= to; j++) {
      ext = bull ? min(ext, c.l[j]) : max(ext, c.h[j]);
    }
    return bull ? c.l[i - 1] < ext : c.h[i - 1] > ext;
  }

  String scenario(EvOutcome o, double mw, double mc) => switch (o) {
        EvOutcome.through => 'broke_through',
        EvOutcome.timeout => 'no_resolution',
        EvOutcome.bounce => mc >= 1 ? 'closed_beyond_then_reclaimed' : (mw >= 1 ? 'wick_through_then_bounce' : 'bounce_inside_gap'),
      };

  return [
    for (final f in found)
      FvgEvent(
        time: c.keys[f.i + 1],
        touchTime: c.keys[f.touch],
        endTime: c.keys[f.end],
        formationMs: c.t[f.i + 1],
        touchMs: c.t[f.touch],
        endMs: c.t[f.end],
        isBull: f.bull,
        edge: f.edge,
        far: f.far,
        gapAtr: (f.edge - f.far).abs() / atr,
        age: f.touch - (f.i + 1),
        maxWick: f.mw,
        maxClose: max(0, f.mc),
        outcome: f.out,
        bars: f.out == EvOutcome.timeout ? null : f.end - f.touch,
        scenario: scenario(f.out, f.mw, f.mc),
        sizeQ: sizeQ((f.edge - f.far).abs() / atr),
        session: sessionForHour(c.time(f.i + 1).hour),
        touchSession: sessionForHour(c.time(f.touch).hour),
        dispQ: quart(disps, (c.c[f.i] - c.o[f.i]).abs() / atr, kDispBuckets),
        htfTrend: trend(f.i + 1, f.bull),
        sweep: sweep(f.i, f.bull),
      ),
  ];
}
