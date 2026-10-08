import 'package:backy/data/events.dart';
import 'package:backy/data/stats.dart';
import 'package:flutter_test/flutter_test.dart';

FvgEvent ev(EvOutcome o, {double wick = 0.3, int? bars = 5, String time = '2022-03-01 01:00:00', String? kind}) => FvgEvent(
      time: time,
      touchTime: time,
      endTime: time,
      formationMs: DateTime.utc(2022, 3, 1, 1).millisecondsSinceEpoch,
      touchMs: 0,
      endMs: 0,
      isBull: true,
      edge: 101,
      far: 100,
      gapAtr: 0.5,
      age: 3,
      maxWick: wick,
      maxClose: 0,
      outcome: o,
      bars: bars,
      scenario: '',
      sizeQ: 'Q2',
      session: 'Asia',
      kind: kind,
    );

List<FvgEvent> many(int n, EvOutcome o, {double wick = 0.3, String? kind}) => [for (var i = 0; i < n; i++) ev(o, wick: wick, kind: kind)];

void main() {
  group('computeStats', () {
    test('rates exclude timeouts from the denominator', () {
      final s = computeStats([...many(6, EvOutcome.bounce), ...many(2, EvOutcome.through), ...many(5, EvOutcome.timeout)]);
      expect(s.total, 13);
      expect(s.resolved, 8);
      expect(s.bounceRate, 6 / 8);
      expect(s.breakRate, 2 / 8);
      expect(s.timeoutShare, 5 / 13);
    });

    test('P(bounce | max_wick ≥ d) uses non-timeout events and hides n < 20', () {
      final evs = [
        ...many(15, EvOutcome.bounce, wick: 0.2),
        ...many(10, EvOutcome.bounce, wick: 0.55),
        ...many(10, EvOutcome.through, wick: 0.7),
        ...many(30, EvOutcome.timeout, wick: 0.9),
      ];
      final s = computeStats(evs);
      expect(s.curve, hasLength(14));
      expect(s.curveN[0], 35);
      expect(s.curve[0], 25 / 35);
      expect(s.curveN[5], 20); // d = 0.5: wick 0.55 and 0.7
      expect(s.curve[5], 0.5);
      expect(s.curveN[6], 10);
      expect(s.curve[6], isNull); // n < 20
    });

    test('d thresholds are inclusive at exact tenths', () {
      final s = computeStats(many(20, EvOutcome.bounce, wick: 0.5));
      expect(s.curveN[5], 20);
    });

    test('histogram buckets bounce wick depth in 0.1 steps, last bucket open', () {
      final s = computeStats([ev(EvOutcome.bounce, wick: 0.05), ev(EvOutcome.bounce, wick: 0.15), ev(EvOutcome.bounce, wick: 3.0), ev(EvOutcome.through, wick: 0.15)]);
      expect(s.hist[0], 1);
      expect(s.hist[1], 1);
      expect(s.hist.last, 1);
      expect(s.hist.fold<int>(0, (a, b) => a + b), 3);
    });

    test('median wick and average bars (timeouts excluded)', () {
      final s = computeStats([ev(EvOutcome.bounce, wick: 0.1, bars: 2), ev(EvOutcome.through, wick: 0.4, bars: 6), ev(EvOutcome.timeout, wick: 0.9, bars: null)]);
      expect(s.medianWick, 0.4);
      expect(s.avgBars, 4);
    });

    test('empty input', () {
      final s = computeStats(const []);
      expect(s.bounceRate, isNull);
      expect(s.medianWick, isNull);
    });
  });

  group('two-proportion z and verdict', () {
    test('pooled z matches fvg_conditions.z2', () {
      // Python: z2(0.6, 1000, 0.5, 1000) = 0.1 / sqrt(0.55*0.45*0.002) = 4.4947...
      final z = zTwoProp(const RateSummary(1000, 600, 1000), const RateSummary(1000, 500, 1000));
      expect(z, closeTo(4.49467, 1e-4));
      expect(zTwoProp(const RateSummary(0, 0, 0), const RateSummary(10, 5, 10)), isNull);
    });

    RateSummary r(int b, int n) => RateSummary(n, b, n);

    test('candidate: real beats fake, control run does not', () {
      final c = Comparison(r(600, 1000), r(500, 1000), r(505, 1000), r(500, 1000));
      expect(c.verdict, Verdict.candidate);
      expect(c.realMinusFakePp, closeTo(10, 1e-9));
      expect(c.controlDiffPp, closeTo(0.5, 1e-9));
      expect(c.edgeOverControlPp, closeTo(9.5, 1e-9));
    });

    test('artifact: the control run shows the same edge', () {
      expect(Comparison(r(600, 1000), r(500, 1000), r(600, 1000), r(500, 1000)).verdict, Verdict.artifact);
    });

    test('no edge: real does not beat fake (z < 2)', () {
      expect(Comparison(r(510, 1000), r(500, 1000), r(500, 1000), r(500, 1000)).verdict, Verdict.noEdge);
      expect(Comparison(r(400, 1000), r(500, 1000), r(500, 1000), r(500, 1000)).verdict, Verdict.noEdge);
    });

    test('needs data: missing files or fewer than 30 resolved in any group', () {
      expect(Comparison(r(600, 1000), r(500, 1000), null, null).verdict, Verdict.needsData);
      expect(Comparison(r(20, 29), r(500, 1000), r(500, 1000), r(500, 1000)).verdict, Verdict.needsData);
    });

    test('rateOf excludes timeouts', () {
      final s = rateOf([...many(3, EvOutcome.bounce), ...many(1, EvOutcome.through), ...many(4, EvOutcome.timeout)]);
      expect([s.n, s.bounces, s.resolved, s.rate], [8, 3, 4, 0.75]);
    });
  });
}
