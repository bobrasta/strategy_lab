import 'dart:math';

import 'events.dart';

/// Bounce rate with timeouts excluded.
class RateSummary {
  const RateSummary(this.n, this.bounces, this.resolved);
  final int n, bounces, resolved;
  double? get rate => resolved == 0 ? null : bounces / resolved;
}

RateSummary rateOf(Iterable<FvgEvent> evs) {
  var n = 0, b = 0, r = 0;
  for (final e in evs) {
    n++;
    if (e.outcome == EvOutcome.timeout) continue;
    r++;
    if (e.outcome == EvOutcome.bounce) b++;
  }
  return RateSummary(n, b, r);
}

/// Pooled two-proportion z-score of a.rate − b.rate.
double? zTwoProp(RateSummary a, RateSummary b) {
  if (a.resolved == 0 || b.resolved == 0) return null;
  final p = (a.bounces + b.bounces) / (a.resolved + b.resolved);
  final se = sqrt(p * (1 - p) * (1 / a.resolved + 1 / b.resolved));
  return se == 0 ? null : (a.rate! - b.rate!) / se;
}

enum Verdict { candidate, artifact, noEdge, needsData }

const kMinVerdictN = 30;
const kZ = 2.0;

/// Real vs fake (random zones) for the active filter and period, checked against the
/// control run (the same procedure on shuffled bars), as in fvg_conditions.py.
/// Candidate: real beats fake (z ≥ 2) and the control run doesn't (z < 2).
/// Artifact: the control run shows the same edge (z ≥ 2), so it comes from the method.
/// No edge: real doesn't beat fake.
class Comparison {
  const Comparison(this.real, this.fake, this.controlReal, this.controlFake);
  final RateSummary real;
  final RateSummary? fake, controlReal, controlFake;

  double? _pp(RateSummary? a, RateSummary? b) => a?.rate == null || b?.rate == null ? null : (a!.rate! - b!.rate!) * 100;
  bool get hasControl => controlReal != null && controlFake != null;
  double? get realMinusFakePp => _pp(real, fake);

  /// Real − fake of the control run in the same bucket.
  double? get controlDiffPp => _pp(controlReal, controlFake);

  /// How much more the real market's edge is than the control run's.
  double? get edgeOverControlPp {
    final a = realMinusFakePp, b = controlDiffPp;
    return a == null || b == null ? null : a - b;
  }

  double? get zRealFake => fake == null ? null : zTwoProp(real, fake!);
  double? get zControl => hasControl ? zTwoProp(controlReal!, controlFake!) : null;

  Verdict get verdict {
    final f = fake, cr = controlReal, cf = controlFake;
    if (f == null || cr == null || cf == null) return Verdict.needsData;
    if ([real, f, cr, cf].any((r) => r.resolved < kMinVerdictN)) return Verdict.needsData;
    final zrf = zRealFake, zc = zControl;
    if (zrf == null || zc == null) return Verdict.needsData;
    if (zrf < kZ) return Verdict.noEdge;
    return zc >= kZ ? Verdict.artifact : Verdict.candidate;
  }
}

const kMinCurveN = 20;
const kHistBuckets = 13; // 0.0–0.1 … 1.1–1.2, ≥1.2 (gap units)

/// All numbers come from the loaded fvg_events.csv (after filters). Nothing is
/// derived from Dart-side gap detection.
class StudyStats {
  const StudyStats({
    required this.total,
    required this.bounces,
    required this.throughs,
    required this.timeouts,
    required this.medianWick,
    required this.avgBars,
    required this.curve,
    required this.curveN,
    required this.hist,
  });

  static const empty = StudyStats(
    total: 0, bounces: 0, throughs: 0, timeouts: 0, medianWick: null, avgBars: null,
    curve: <double?>[], curveN: <int>[], hist: <int>[],
  );

  final int total, bounces, throughs, timeouts;
  final double? medianWick, avgBars;

  /// P(bounce | max_wick ≥ d), d = 0.0 … 1.3 step 0.1; null where n < 20.
  final List<double?> curve;
  final List<int> curveN;

  /// max_wick of bounce events.
  final List<int> hist;

  int get resolved => bounces + throughs;

  /// Timeouts excluded from the denominator.
  double? get bounceRate => resolved == 0 ? null : bounces / resolved;
  double? get breakRate => resolved == 0 ? null : throughs / resolved;
  double get timeoutShare => total == 0 ? 0 : timeouts / total;
}

/// P(bounce | max_wick ≥ d) for d = 0.0 … 1.3 (step 0.1) over non-timeout events, null where
/// n < [kMinCurveN]. One pass: each event counts for every threshold up to the deepest it reached.
({List<double?> curve, List<int> curveN}) depthCurve(Iterable<FvgEvent> evs) {
  const steps = 14;
  double th(int k) => k / 10 - 1e-9; // same thresholds as the study's d loop
  final n = List<int>.filled(steps, 0), nb = List<int>.filled(steps, 0);
  for (final e in evs) {
    if (e.outcome == EvOutcome.timeout) continue;
    final w = e.maxWick;
    var k = min(steps - 1, ((w + 1e-9) * 10).floor());
    while (k < steps - 1 && w >= th(k + 1)) {
      k++;
    }
    while (k >= 0 && w < th(k)) {
      k--;
    }
    if (k < 0) continue;
    n[k]++;
    if (e.outcome == EvOutcome.bounce) nb[k]++;
  }
  for (var k = steps - 2; k >= 0; k--) {
    n[k] += n[k + 1];
    nb[k] += nb[k + 1];
  }
  return (curve: [for (var k = 0; k < steps; k++) n[k] < kMinCurveN ? null : nb[k] / n[k]], curveN: n);
}

StudyStats computeStats(List<FvgEvent> evs) {
  var b = 0, t = 0, to = 0, barsSum = 0, barsN = 0;
  final wicks = <double>[];
  final hist = List<int>.filled(kHistBuckets, 0);
  for (final e in evs) {
    wicks.add(e.maxWick);
    switch (e.outcome) {
      case EvOutcome.bounce:
        b++;
        hist[min(kHistBuckets - 1, max(0, (e.maxWick * 10).floor()))]++;
      case EvOutcome.through:
        t++;
      case EvOutcome.timeout:
        to++;
    }
    if (e.outcome != EvOutcome.timeout && e.bars != null) {
      barsSum += e.bars!;
      barsN++;
    }
  }
  wicks.sort();

  final (:curve, :curveN) = depthCurve(evs);

  return StudyStats(
    total: evs.length,
    bounces: b,
    throughs: t,
    timeouts: to,
    medianWick: wicks.isEmpty ? null : wicks[wicks.length ~/ 2],
    avgBars: barsN == 0 ? null : barsSum / barsN,
    curve: curve,
    curveN: curveN,
    hist: hist,
  );
}
