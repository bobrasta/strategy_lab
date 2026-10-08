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

/// Real vs fake (random zones) vs control, for the active filter and period.
/// Candidate: real beats fake AND control (z ≥ 2 each).
/// Artifact: real beats fake but real ≈ control (|z| < 2).
/// No edge: real doesn't beat fake (or loses to control).
class Comparison {
  const Comparison(this.real, this.fake, this.control);
  final RateSummary real;
  final RateSummary? fake, control;

  double? _pp(RateSummary? a, RateSummary? b) => a?.rate == null || b?.rate == null ? null : (a!.rate! - b!.rate!) * 100;
  double? get realMinusFakePp => _pp(real, fake);
  double? get controlMinusFakePp => _pp(control, fake);
  double? get realMinusControlPp => _pp(real, control);
  double? get zRealFake => fake == null ? null : zTwoProp(real, fake!);
  double? get zControlFake => fake == null || control == null ? null : zTwoProp(control!, fake!);
  double? get zRealControl => control == null ? null : zTwoProp(real, control!);

  Verdict get verdict {
    final f = fake, c = control;
    if (f == null || c == null || real.resolved < kMinVerdictN || f.resolved < kMinVerdictN || c.resolved < kMinVerdictN) {
      return Verdict.needsData;
    }
    final zrf = zRealFake, zrc = zRealControl;
    if (zrf == null || zrf < kZ) return Verdict.noEdge;
    if (zrc != null && zrc >= kZ) return Verdict.candidate;
    if (zrc == null || zrc.abs() < kZ) return Verdict.artifact;
    return Verdict.noEdge;
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

  final curve = <double?>[], curveN = <int>[];
  for (var k = 0; k <= 13; k++) {
    final d = k / 10 - 1e-9;
    var n = 0, nb = 0;
    for (final e in evs) {
      if (e.outcome == EvOutcome.timeout || e.maxWick < d) continue;
      n++;
      if (e.outcome == EvOutcome.bounce) nb++;
    }
    curveN.add(n);
    curve.add(n < kMinCurveN ? null : nb / n);
  }

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
