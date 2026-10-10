import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:strategy_lab/chart/chart_geometry.dart';
import 'package:strategy_lab/chart/chart_layer.dart';
import 'package:strategy_lab/chart/trades_layer.dart';
import 'package:strategy_lab/state/app_state.dart';
import 'package:strategy_lab/theme.dart';
import 'package:strategy_lab/widgets/graph_view.dart';
import 'package:strategy_lab/widgets/tables.dart';

import 'support.dart';

LayerContext ctx(AppState s) => LayerContext(state: s, candles: s.candles!, cursor: s.visibleCursor, nowMs: s.nowMs);
ChartGeometry geo(AppState s) {
  s.fit();
  return ChartGeometry.compute(const Size(1200, 700), s, s.candles!, s.visibleCursor, 0);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('replay on M1: trades, position, equity, drawings, tables never read past the cursor bar', () async {
    final s = await openFakeRun(writeFakeRun());
    expect(s.timeframe, 'M1');
    s.enterReplay();
    s.startAt(0);
    final run = s.run!;
    for (var bar = 0; bar < 120; bar++) {
      expect(s.visibleCursor, bar);
      final now = s.nowMs;
      expect(now, at(bar, 59), reason: 'now = the cursor bar\'s last tick (+59 s)');
      final g = geo(s);
      final c = ctx(s);
      final shown = TradesLayer.visible(g, c).toList();
      expect(shown.map((t) => t.ticket), [if (bar >= 10) 1, if (bar >= 65) 3], reason: 'bar $bar');
      for (final t in shown) {
        expect(TradesLayer.closed(t, c), t.closeMs <= now, reason: 'exit of #${t.ticket} at bar $bar');
      }
      // trade #1 closes at 00:40:20 (bar 40), #3 at 01:30:40 (bar 90)
      final pos = run.positionAt(now);
      expect(pos?.ticket, bar >= 10 && bar < 40 ? 1 : (bar >= 65 && bar < 90 ? 3 : null), reason: 'position at bar $bar');
      final row = run.equityAt(now)!;
      expect(row.ms, lessThanOrEqualTo(now));
      expect(row.ms, at(bar, 59), reason: 'the bar row, not an earlier deal row');
      expect(row.profit, (bar >= 10 && bar < 40) || (bar >= 65 && bar < 90) ? (bar - 9).toDouble() : 0.0);
      final objs = {for (final o in run.drawingsAt(now)) o.name: o};
      expect(objs.containsKey('z'), bar >= 5 && bar < 80, reason: 'zone z at bar $bar');
      if (objs['z'] != null) expect(objs['z']!.t2, bar >= 50 ? at(50) : null, reason: 'zone stays open-ended until the move at 00:50');
      expect(objs.containsKey('m'), bar >= 10);
      expect(tradesShown(s), (bar >= 10 ? 1 : 0) + (bar >= 65 ? 1 : 0));
      expect(run.dealsBy(now), [10, 40, 65, 90].where((m) => bar >= m).length);
      expect(run.journalBy(now), (bar >= 10 ? 1 : 0) + (bar >= 65 ? 1 : 0));
      s.step(1);
    }
  });

  test('stepping back rebuilds the drawing state (a deleted zone comes back)', () async {
    final s = await openFakeRun(writeFakeRun());
    s.enterReplay();
    s.startAt(85);
    expect(s.run!.drawingsAt(s.nowMs).map((o) => o.name), isNot(contains('z')));
    s.step(-20); // bar 65: z exists, already moved
    final z = s.run!.drawingsAt(s.nowMs).firstWhere((o) => o.name == 'z');
    expect(z.t2, at(50));
    s.step(-20); // bar 45: z exists, still open-ended
    expect(s.run!.drawingsAt(s.nowMs).firstWhere((o) => o.name == 'z').t2, isNull);
  });

  test('on M5 the cursor bar ends at +4:59; a trade inside it shows once that bar is the cursor', () async {
    final s = await openFakeRun(writeFakeRun());
    await s.setTimeframe('M5');
    s.enterReplay();
    s.startAt(1); // 00:05 bar, ends 00:09:59
    expect(s.nowMs, at(9, 59));
    expect(TradesLayer.visible(geo(s), ctx(s)), isEmpty);
    s.step(1); // 00:10 bar holds the 00:10:00 entry
    expect(TradesLayer.visible(geo(s), ctx(s)).map((t) => t.ticket), [1]);
    // trade #1 closes 00:40:20: inside the 00:40 bar (index 8), not before it
    s.startAt(7);
    expect(TradesLayer.closed(s.run!.tradeByTicket(1)!, ctx(s)), isFalse);
    s.step(1);
    expect(TradesLayer.closed(s.run!.tradeByTicket(1)!, ctx(s)), isTrue);
  });

  test('switching timeframe in replay never moves "now" later', () async {
    final s = await openFakeRun(writeFakeRun());
    s.enterReplay();
    s.startAt(37); // M1 00:37, now 00:37:59
    await s.setTimeframe('M5');
    expect(s.nowMs, lessThanOrEqualTo(at(37, 59)));
    expect(s.nowMs, at(34, 59), reason: 'the last M5 bar fully known by then');
  });

  test('autoscale only reads bars at or before the cursor', () async {
    final s = await openFakeRun(writeFakeRun());
    s.enterReplay();
    s.startAt(29);
    double hi() => ChartGeometry.compute(const Size(1200, 700), s, s.candles!, s.visibleCursor, 0).hi;
    final before = hi();
    s.scalePrice(0.5);
    s.shiftPrice(0.3);
    s.resetPriceScale();
    expect(hi(), before);
    s.step(1); // bar 30 has the 100.6 high
    expect(hi(), greaterThan(before));
  });

  test('the equity graph draws only buckets that end by the cut, then the exact row at it', () async {
    final s = await openFakeRun(writeFakeRun());
    final store = s.run!.equity!;
    final cut = at(50, 30);
    final pts = graphPoints(GraphSeries(store: store, label: '', equityColor: C.blue, balanceColor: C.text, cutMs: cut));
    expect(pts.every((p) => p.ms <= cut), isTrue);
    expect(pts.last.ms, at(49, 59), reason: 'the last row stamped by 00:50:30 is the 00:49 bar row');
    expect(graphPoints(GraphSeries(store: store, label: '', equityColor: C.blue, balanceColor: C.text)).last.ms, at(119, 59));
  });

  test('next trade (N) stops at the next entry or exit bar', () async {
    final s = await openFakeRun(writeFakeRun());
    s.enterReplay();
    s.startAt(0);
    final stops = <int>[];
    for (var i = 0; i < 6; i++) {
      s.nextTrade();
      stops.add(s.visibleCursor);
    }
    expect(stops, [10, 40, 65, 90, 90, 90]);
  });

  test('replay trade starts 50 bars before the entry, with the trade selected', () async {
    final s = await openFakeRun(writeFakeRun());
    s.replayTrade(3);
    expect(s.isReplay, isTrue);
    expect(s.visibleCursor, 15);
    expect(s.selectedTrade, 3);
  });

  test('100 bars/s advances ~100 bars per second with at most ~60 repaints', () async {
    final s = await openFakeRun(writeFakeRun());
    s.enterReplay();
    s.startAt(0);
    s.setSpeed(100);
    var notes = 0;
    s.addListener(() => notes++);
    s.togglePlay();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    s.togglePlay();
    expect(s.visibleCursor, inInclusiveRange(40, 51), reason: '~50 bars in 0.5 s');
    expect(notes, lessThanOrEqualTo(36));
  });
}
