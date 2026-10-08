import 'package:backy/data/candles.dart';
import 'package:backy/data/loaders.dart';
import 'package:backy/data/resample.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

String m1Csv(List<List<double>> bars, DateTime start) {
  final b = StringBuffer('time,open,high,low,close,volume\n');
  for (var i = 0; i < bars.length; i++) {
    final v = bars[i];
    b.writeln('${key(start.add(Duration(minutes: i)))},${v[0]},${v[1]},${v[2]},${v[3]},${v[4]}');
  }
  return b.toString();
}

void main() {
  test('M1 → M5: open first, high max, low min, close last, volume sum; UTC buckets', () {
    final bars = [for (var i = 0; i < 12; i++) <double>[10.0 + i, 11.0 + i, 9.0 + i, 10.5 + i, 1]];
    bars[7][1] = 99; // highest high in the second bucket
    bars[6][2] = 1; // lowest low in the second bucket
    // starts at 00:02, so the first M5 bucket (00:00) holds 3 bars
    final c = parseCandlesFile(writeTemp('m1.csv', m1Csv(bars, DateTime.utc(2022, 3, 1, 0, 2))));
    expect(c.tf, 'M1');
    final m5 = resample(c, 5);
    expect(m5.tf, 'M5');
    expect(m5.keys, ['2022-03-01 00:00:00', '2022-03-01 00:05:00', '2022-03-01 00:10:00']);
    expect([m5.o[0], m5.h[0], m5.l[0], m5.c[0], m5.v[0]], [10, 13, 9, 12.5, 3]);
    expect([m5.o[1], m5.h[1], m5.l[1], m5.c[1], m5.v[1]], [13, 99, 1, 17.5, 5]);
    expect(m5.length, 3);
  });

  test('gaps in M1 (weekends) produce no empty bars', () {
    final a = m1Csv([for (var i = 0; i < 3; i++) <double>[1, 2, 0, 1, 1]], DateTime.utc(2022, 3, 4, 21, 57));
    final b = m1Csv([for (var i = 0; i < 3; i++) <double>[5, 6, 4, 5, 1]], DateTime.utc(2022, 3, 6, 22, 0)).split('\n').skip(1).join('\n');
    final h1 = resample(parseCandlesFile(writeTemp('m1.csv', '$a$b')), 60);
    expect(h1.keys, ['2022-03-04 21:00:00', '2022-03-06 22:00:00']);
  });

  test('M1 file resampled to M15 reproduces the M15 file\'s OHLC', () {
    final m1 = parseCandlesFile(fx(kM1)), m15 = parseCandlesFile(fx(kM15));
    expect(m1.length, 1772275);
    final r = resample(m1, 15);
    final idx = r.index;
    var compared = 0, missing = 0, worst = 0.0;
    String? worstAt;
    // every 50th M15 bar across the five years (~2,400 bars) plus the first and last
    for (final i in {0, m15.length - 1, for (var i = 0; i < m15.length; i += 50) i}) {
      final j = idx[m15.keys[i]];
      if (j == null) {
        missing++;
        continue;
      }
      for (final (a, b) in [(m15.o[i], r.o[j]), (m15.h[i], r.h[j]), (m15.l[i], r.l[j]), (m15.c[i], r.c[j])]) {
        final d = (a - b).abs();
        if (d > worst) {
          worst = d;
          worstAt = m15.keys[i];
        }
      }
      compared++;
    }
    // ignore: avoid_print
    print('M1→M15: compared $compared bars, $missing not in the resample, worst |Δ| = $worst at $worstAt; '
        'resampled ${r.length} bars vs ${m15.length} in the M15 file');
    expect(missing, 0);
    expect(worst, lessThan(1e-6));
  }, skip: skipUnlessFxdata([kM1, kM15]), timeout: const Timeout(Duration(minutes: 3)));

  test('timeframe labels', () {
    expect([1, 5, 15, 60].map(tfLabel), ['M1', 'M5', 'M15', 'H1']);
    expect(['M1', 'M5', 'M15', 'H1'].map(tfMinutes), [1, 5, 15, 60]);
  });
}
