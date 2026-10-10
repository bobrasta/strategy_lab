import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strategy_lab/run/equity_store.dart';
import 'package:strategy_lab/theme.dart';
import 'package:strategy_lab/widgets/graph_view.dart';

import 'equity_store_test.dart' show equityCsv;
import 'support.dart';

void main() {
  // 3000 one-minute rows (+ a deal row every 97 min), 2022-03-01 00:00:59 .. 02:59:59 UTC.
  final (csv, rows) = equityCsv(3000);
  late String path;
  late EquityIndex ix;
  setUpAll(() {
    path = writeTemp('equity.csv', csv);
    ix = scanEquityFile(path, targetBuckets: 100);
  });

  test('window buckets cover exactly the rows stamped in the window and pick their values', () {
    final from = at(700), to = at(1300, 59);
    final b0 = ix.blockMs.lastIndexWhere((m) => m <= from), b1 = ix.blockMs.lastIndexWhere((m) => m <= to) + 1;
    final g = scanEquityRange(path, ix.columns, ix.blockOff[b0], b1 < ix.blockOff.length ? ix.blockOff[b1] : ix.fileLen, from, to, 7);
    final inside = rows.where((r) => r.$1 >= from && r.$1 <= to).toList();
    expect(g.length, (inside.length / 7).ceil());
    var r0 = 0;
    for (var k = 0; k < g.length; k++) {
      final part = inside.sublist(r0, (r0 + 7).clamp(0, inside.length));
      expect(g.firstMs[k], part.first.$1);
      expect(g.ms[k], part.last.$1);
      expect(g.equity[k], closeTo(part.last.$3, 1e-9));
      expect(g.eqMin[k], closeTo(part.map((r) => r.$4).reduce((a, b) => a < b ? a : b), 1e-9));
      expect(g.eqMax[k], closeTo(part.map((r) => r.$3).reduce((a, b) => a > b ? a : b), 1e-9));
      r0 += part.length;
    }
    expect(r0, inside.length);
  });

  test('bucketsIn (isolate) is about one bucket per target slot and stays in the window', () async {
    final st = EquityStore(path, ix);
    final from = at(1000), to = at(1060);
    final g = await st.bucketsIn(from, to, 200);
    expect(g.perBucket, 1, reason: '~62 rows in the window fit 200 slots one row each');
    expect(g.ms.every((m) => m >= from && m <= to), isTrue);
    expect(g.length, rows.where((r) => r.$1 >= from && r.$1 <= to).length);
    st.close();
  });

  test('window points: the buckets in it plus one neighbour each side; never past the replay cut', () async {
    final st = EquityStore(path, ix);
    final fine = await st.bucketsIn(at(900), at(1500), 1000);
    final s = GraphSeries(store: st, label: '', equityColor: C.blue, balanceColor: C.text);
    final pts = graphPoints(s, buckets: fine, from: at(1000), to: at(1200));
    expect(pts.first.ms, lessThan(at(1000)));
    expect(pts.last.ms, greaterThan(at(1200)));
    expect(pts.where((p) => p.ms < at(1000) || p.ms > at(1200)).length, 2);

    final cut = at(1100, 30);
    final cutPts = graphPoints(GraphSeries(store: st, label: '', equityColor: C.blue, balanceColor: C.text, cutMs: cut), buckets: fine, from: at(1000), to: at(1200));
    expect(cutPts.every((p) => p.ms <= cut), isTrue, reason: 'no lookahead in a zoomed replay');
    expect(cutPts.last.ms, at(1099, 59), reason: 'the last row stamped by 18:20:30 is the 18:19 bar row');
    st.close();
  });

  test('time ticks: at least ~90 px apart, hours when zoomed in, years for the whole data', () {
    const hour = 3600 * 1000;
    final h = timeTicks(at(0), at(0) + 10 * hour, 1000);
    expect(h.length, inInclusiveRange(5, 11));
    expect(h.first.$2, '01:00');
    final y = timeTicks(DateTime.utc(2021).millisecondsSinceEpoch, DateTime.utc(2026, 10, 8).millisecondsSinceEpoch, 1000);
    expect(y.map((t) => t.$2), ['2022', '2023', '2024', '2025', '2026']);
    for (final ticks in [h, y, timeTicks(at(0), at(0) + 40 * 24 * hour, 800)]) {
      for (var i = 1; i < ticks.length; i++) {
        expect(ticks[i].$1 - ticks[i - 1].$1, greaterThan(0));
      }
    }
  });

  testWidgets('wheel zooms at the pointer, "Full range" and double-click reset', (t) async {
    await loadAppFont();
    final st = EquityStore(path, ix);
    await t.binding.setSurfaceSize(const Size(1000, 400));
    await t.pumpWidget(MaterialApp(
      home: Scaffold(body: EquityGraph(series: [GraphSeries(store: st, label: '', equityColor: C.blue, balanceColor: C.text)])),
    ));
    expect(find.text('Full range'), findsNothing);
    final center = t.getCenter(find.byType(EquityGraph));
    await t.sendEventToBinding(PointerScrollEvent(position: center, scrollDelta: const Offset(0, -400)));
    await t.pump();
    expect(find.text('Full range'), findsOneWidget);
    await t.tap(find.text('Full range'));
    await t.pump();
    expect(find.text('Full range'), findsNothing);

    await t.sendEventToBinding(PointerScrollEvent(position: center, scrollDelta: const Offset(0, -400)));
    await t.pump();
    await t.tapAt(center, kind: PointerDeviceKind.mouse);
    await t.pump(const Duration(milliseconds: 50));
    await t.tapAt(center, kind: PointerDeviceKind.mouse);
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('Full range'), findsNothing);
    st.close();
    await t.binding.setSurfaceSize(null);
  });
}
