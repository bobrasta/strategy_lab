import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strategy_lab/run/equity_store.dart';

import 'support.dart';

/// [n] rows, one per minute at +59 s, with a deal row every 97 minutes; values with 17-digit tails.
(String, List<(int, double, double, double)>) equityCsv(int n, {bool newColumns = true}) {
  final b = StringBuffer(newColumns ? 'time,kind,balance,equity,equity_min,margin,profit,drawdown,drawdown_pct\n' : 'time,kind,balance,equity,equity_min,margin\n');
  final rows = <(int, double, double, double)>[];
  for (var m = 0; m < n; m++) {
    if (m % 97 == 5) {
      final bal = 10000 + m / 3;
      b.writeln('${atKey(m, 0)},deal,$bal,$bal,$bal,0${newColumns ? ',0,0,0' : ''}');
      rows.add((at(m), bal, bal, bal));
    }
    final bal = 10000 + m / 3, eq = bal + (m % 13) * 0.1 - 0.6, mn = eq - (m % 5) * 0.37;
    b.writeln('${atKey(m, 59)},bar,$bal,$eq,$mn,12.5${newColumns ? ',${eq - bal},${(m % 7) * 1.1},${(m % 7) * 0.011}' : ''}');
    rows.add((at(m, 59), bal, eq, mn));
  }
  return (b.toString(), rows);
}

void main() {
  test('at(ms) returns exactly the last row stamped at or before ms, across block boundaries', () {
    final (csv, rows) = equityCsv(3000);
    final path = writeTemp('equity.csv', csv);
    final ix = scanEquityFile(path, targetBuckets: 100);
    expect(ix.rows, rows.length);
    expect(ix.blockMs.length, (rows.length + 511) ~/ 512);
    final st = EquityStore(path, ix);
    expect(st.at(at(0) - 1), isNull, reason: 'nothing before the first row');
    for (var probe = at(0, 59); probe <= at(3001); probe += 17000) {
      final want = rows.lastWhere((r) => r.$1 <= probe);
      final got = st.at(probe)!;
      expect(got.ms, want.$1, reason: 'probe $probe');
      expect([got.balance, got.equity, got.equityMin], [want.$2, want.$3, want.$4], reason: 'exact values at $probe');
    }
    st.close();
  });

  test('graph buckets: last balance/equity, lowest equity_min, highest equity, deepest drawdown, ≤ target count', () {
    final (csv, rows) = equityCsv(3000);
    final ix = scanEquityFile(writeTemp('equity.csv', csv), targetBuckets: 100);
    expect(ix.buckets, inInclusiveRange(50, 100));
    var r0 = 0;
    for (var k = 0; k < ix.buckets; k++) {
      final r1 = rows.indexWhere((r) => r.$1 == ix.gMs[k], r0);
      final part = rows.sublist(r0, r1 + 1);
      expect(ix.gFirstMs[k], part.first.$1);
      expect(ix.gBalance[k], closeTo(part.last.$2, 1e-9));
      expect(ix.gEquity[k], closeTo(part.last.$3, 1e-9));
      expect(ix.gEqMin[k], closeTo(part.map((r) => r.$4).reduce((a, b) => a < b ? a : b), 1e-9));
      expect(ix.gEqMax[k], closeTo(part.map((r) => r.$3).reduce((a, b) => a > b ? a : b), 1e-9));
      r0 = r1 + 1;
    }
    expect(r0, rows.length, reason: 'buckets cover every row');
  });

  test('runs written before profit/drawdown existed still load; those fields are null', () {
    final (csv, _) = equityCsv(50, newColumns: false);
    final path = writeTemp('equity.csv', csv);
    final ix = scanEquityFile(path);
    expect(ix.hasProfit, isFalse);
    final r = EquityStore(path, ix).at(at(20, 59))!;
    expect(r.profit, isNull);
    expect(r.drawdownPct, isNull);
  });

  test('CRLF line ends and a missing final newline are fine; a missing file is a clear error', () {
    final (csv, rows) = equityCsv(40);
    final path = writeTemp('equity.csv', csv.replaceAll('\n', '\r\n').trimRight());
    final ix = scanEquityFile(path);
    expect(ix.rows, rows.length);
    expect(EquityStore(path, ix).at(at(39, 59))!.equity, rows.last.$3);
    expect(() => scanEquityFile('${tempDir().path}/nope.csv'), throwsA(isA<Object>()));
    expect(File(path).existsSync(), isTrue);
  });
}
