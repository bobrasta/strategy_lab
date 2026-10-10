import 'package:strategy_lab/data/candles.dart';
import 'package:strategy_lab/data/loaders.dart';
import 'package:strategy_lab/data/resample.dart';
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
    expect([for (var i = 0; i < m5.length; i++) m5.key(i)], ['2022-03-01 00:00:00', '2022-03-01 00:05:00', '2022-03-01 00:10:00']);
    expect([m5.o[0], m5.h[0], m5.l[0], m5.c[0], m5.v[0]], [10, 13, 9, 12.5, 3]);
    expect([m5.o[1], m5.h[1], m5.l[1], m5.c[1], m5.v[1]], [13, 99, 1, 17.5, 5]);
    expect(m5.length, 3);
  });

  test('gaps in M1 (weekends) produce no empty bars', () {
    final a = m1Csv([for (var i = 0; i < 3; i++) <double>[1, 2, 0, 1, 1]], DateTime.utc(2022, 3, 4, 21, 57));
    final b = m1Csv([for (var i = 0; i < 3; i++) <double>[5, 6, 4, 5, 1]], DateTime.utc(2022, 3, 6, 22, 0)).split('\n').skip(1).join('\n');
    final h1 = resample(parseCandlesFile(writeTemp('m1.csv', '$a$b')), 60);
    expect([for (var i = 0; i < h1.length; i++) h1.key(i)], ['2022-03-04 21:00:00', '2022-03-06 22:00:00']);
  });

  test('M1 file resampled to M15 reproduces the M15 file bar for bar', () {
    final m1 = parseCandlesFile(fx(kM1)), m15 = parseCandlesFile(fx(kM15));
    final r = resample(m1, 15);
    expect(r.length, m15.length);
    var worst = 0.0;
    for (var i = 0; i < m15.length; i++) {
      expect(r.t[i], m15.t[i]);
      for (final (a, b) in [(m15.o[i], r.o[i]), (m15.h[i], r.h[i]), (m15.l[i], r.l[i]), (m15.c[i], r.c[i])]) {
        if ((a - b).abs() > worst) worst = (a - b).abs();
      }
    }
    expect(worst, 0, reason: 'same doubles: the M15 file was resampled from the same ticks');
  }, skip: skipUnlessFxdata([kM1, kM15]), timeout: const Timeout(Duration(minutes: 3)));

  test('head() is a no-copy view cut at a bar', () {
    final c = parseCandlesFile(writeTemp('m1.csv', candlesCsv(10, minutes: 1)));
    final h = c.head(4);
    expect(h.length, 4);
    expect(h.t.buffer.lengthInBytes, c.t.buffer.lengthInBytes, reason: 'a view on the full buffer');
    expect(c.barAt(c.t[3] + 30000), 3);
    expect(c.endMs(3), c.t[3] + 59000);
  });

  test('timeframe labels', () {
    expect([1, 5, 15, 60].map(tfLabel), ['M1', 'M5', 'M15', 'H1']);
    expect(['M1', 'M5', 'M15', 'H1'].map(tfMinutes), [1, 5, 15, 60]);
  });
}
