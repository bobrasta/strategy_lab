import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:strategy_lab/util/fastparse.dart';

Uint8List b(String s) => Uint8List.fromList(s.codeUnits);

void main() {
  test('parseDoubleBytes is bit-identical to double.parse (engine shortest round-trip output and prices)', () {
    final r = Random(7);
    final samples = <String>[
      '0', '-0', '1904.998', '10544.7318125', '10542.981812500002', '-0.35000000000000003', '115.69999999999936',
      '1e-05', '2.5e+20', '1.7976931348623157e308', '5e-324', '0.1', '123456789012345', '1234567890123456', '0.000000000000000000000001',
    ];
    for (var i = 0; i < 200000; i++) {
      final x = switch (i % 4) {
        0 => (r.nextDouble() * 5000).toString(), // Dart shortest form: up to 17 digits
        1 => (r.nextInt(5000000) / 1000).toStringAsFixed(3), // prices
        2 => (r.nextDouble() * 1e6 - 5e5).toStringAsFixed(r.nextInt(10)),
        _ => (r.nextDouble() * pow(10, r.nextInt(40) - 20)).toString(),
      };
      samples.add(x);
    }
    for (final s in samples) {
      final want = double.parse(s), got = parseDoubleBytes(b(s), 0, s.length);
      expect(got, isNotNull, reason: s);
      int bits(double v) => (ByteData(8)..setFloat64(0, v)).getUint64(0);
      expect(bits(got!), bits(want), reason: s);
    }
    expect(parseDoubleBytes(b('x1'), 0, 2), isNull);
    expect(parseDoubleBytes(b('.'), 0, 1), isNull);
    expect(parseDoubleBytes(b(''), 0, 0), isNull);
  });

  test('parseDoubleApprox stays within a few ulp (plotting only)', () {
    final r = Random(3);
    for (var i = 0; i < 50000; i++) {
      final s = (r.nextDouble() * 20000).toString();
      final want = double.parse(s), got = parseDoubleApprox(b(s), 0, s.length)!;
      expect((got - want).abs(), lessThanOrEqualTo(want.abs() * 1e-15), reason: s);
    }
  });

  test('parseTimeBytes matches DateTime.utc and rejects junk', () {
    final r = Random(11);
    for (var i = 0; i < 20000; i++) {
      final t = DateTime.utc(1990 + r.nextInt(60), 1 + r.nextInt(12), 1 + r.nextInt(28), r.nextInt(24), r.nextInt(60), r.nextInt(60));
      String p(int v) => v.toString().padLeft(2, '0');
      final s = '${t.year}-${p(t.month)}-${p(t.day)} ${p(t.hour)}:${p(t.minute)}:${p(t.second)}';
      expect(parseTimeBytes(b(s), 0, s.length), t.millisecondsSinceEpoch, reason: s);
      expect(parseTimeBytes(b(s.substring(0, 16)), 0, 16), t.millisecondsSinceEpoch - t.second * 1000);
    }
    for (final bad in ['2021-13-01 00:00:00', '2021-01-01T00:00:00', '2021-01-01 24:00:00', '2021-1-01 00:00:00', 'abcd-ef-gh ij:kl:mn']) {
      expect(parseTimeBytes(b(bad), 0, bad.length), isNull, reason: bad);
    }
  });
}
