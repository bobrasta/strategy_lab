// The chart's volume profile tool (VolumeProfileTool): drag (or click) from candle to candle → a
// volume_profile indicator instance with that range, computed by the (fake) engine; resize by an
// edge, select, Delete, Esc; replay can't reach past the cursor; an unbuilt indicator is built first.
// The fake run's chart is M1 from 2022-03-01 00:00 UTC, so bar i opens at 00:i.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strategy_lab/chart/chart_geometry.dart';
import 'package:strategy_lab/chart/price_chart.dart';
import 'package:strategy_lab/indicators/input_time.dart';
import 'package:strategy_lab/main.dart';
import 'package:strategy_lab/state/lab_state.dart';

import 'support.dart';

Future<void> settle(WidgetTester t, bool Function() cond) async {
  for (var k = 0; k < 500 && !cond(); k++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await t.pump();
  }
  expect(cond(), isTrue, reason: 'timed out');
}

Future<(LabState, M7Engine)> pumpLab(WidgetTester t, {String status = 'built'}) async {
  await loadAppFont();
  t.view.physicalSize = const Size(1440, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  late LabState lab;
  final m = M7Engine()..status = {'volume_profile': status};
  await t.runAsync(() async {
    lab = await testLab(engine: m.engine);
    await lab.indicators.refresh();
    await openFakeRun(writeFakeRun(), into: lab.chart);
  });
  await t.pumpWidget(StrategyLabApp(lab: lab, manageEngine: false));
  await t.pump(const Duration(milliseconds: 50));
  return (lab, m);
}

/// Global position of chart bar [bar]'s centre at [price] (or mid-plot).
Offset posOf(WidgetTester t, LabState lab, int bar, {double? price, double dx = 0}) {
  final s = lab.chart, f = find.byType(PriceChart);
  final g = ChartGeometry.compute(t.getSize(f), s, s.candles!, s.visibleCursor, 0);
  return t.getTopLeft(f) + Offset(g.x(bar) + dx, price == null ? (g.top + g.bottom) / 2 : g.y(price));
}

ChartGeometry geo(WidgetTester t, LabState lab) =>
    ChartGeometry.compute(t.getSize(find.byType(PriceChart)), lab.chart, lab.chart.candles!, lab.chart.visibleCursor, 0);

Future<void> drag(WidgetTester t, Offset from, Offset to) async {
  final gst = await t.startGesture(from, kind: PointerDeviceKind.mouse);
  for (var k = 1; k <= 8; k++) {
    await gst.moveTo(Offset.lerp(from, to, k / 8)!);
    await t.pump();
  }
  await gst.up();
  await t.pump();
}

void main() {
  group('time inputs read as the engine reads them', () {
    test('formats accepted and refused like hm::Program::StringToTime', () {
      int u(int y, int mo, int d, [int h = 0, int mi = 0, int s = 0]) => DateTime.utc(y, mo, d, h, mi, s).millisecondsSinceEpoch;
      expect(parseInputTime('2022.03.06 00:00'), u(2022, 3, 6));
      expect(parseInputTime('2024-01-10'), u(2024, 1, 10));
      expect(parseInputTime('2024-01-10T05:06:07'), u(2024, 1, 10, 5, 6, 7));
      expect(parseInputTime('  2024.1.2   3:4 '), u(2024, 1, 2, 3, 4));
      expect(parseInputTime('2024.02.29 23:59:59'), u(2024, 2, 29, 23, 59, 59));
      for (final bad in ['nonsense', '', '2023.02.29', '2024.01.10 24:00', '2024.01-10', '2024.01.10 5', '1969.12.31', '2024.04.31', '2024.01.10 05:06:07:08']) {
        expect(parseInputTime(bad), isNull, reason: bad);
      }
      expect(parseInputTime(null), isNull);
    });

    test('written as YYYY.MM.DD HH:MI UTC and read back', () {
      final ms = DateTime.utc(2025, 7, 4, 9, 5).millisecondsSinceEpoch;
      expect(fmtInputTime(ms), '2025.07.04 09:05');
      expect(parseInputTime(fmtInputTime(ms)), ms);
    });
  });

  testWidgets('drag from candle to candle → a volume_profile instance for exactly those bars', (t) async {
    final (lab, m) = await pumpLab(t);
    final tool = lab.vpTool, ind = lab.indicators;
    m.onStart = (job) => m.finish(job);

    await t.tap(find.byKey(const ValueKey('vp-tool')));
    await t.pump();
    expect(tool.active, isTrue);
    expect(find.byKey(const ValueKey('vp-hint')), findsOneWidget);

    // Left to right, 00:20 .. 00:35 → [00:20, 00:36)
    await drag(t, posOf(t, lab, 20), posOf(t, lab, 35));
    expect(ind.instances, hasLength(1));
    final i = ind.instances.single;
    expect(i.name, 'volume_profile');
    expect(i.inputs, {'RangeFrom': '2022.03.01 00:20', 'RangeTo': '2022.03.01 00:36'});
    expect(m.starts.single['inputs'], i.inputs);
    expect(m.starts.single['indicator'], 'volume_profile');
    expect(tool.active, isFalse, reason: 'one range per pick, as in TradingView');
    expect(tool.selected, i);
    expect(find.byKey(const ValueKey('vp-hint')), findsNothing);
    expect(lab.settings.indicators.single.inputs, i.inputs, reason: 'persisted like any attached indicator');
    await settle(t, () => i.state == 'ok');
    expect(t.takeException(), isNull);

    // Right to left is the same range, ordered.
    await t.tap(find.byKey(const ValueKey('vp-tool')));
    await t.pump();
    await drag(t, posOf(t, lab, 50), posOf(t, lab, 41));
    expect(ind.instances.last.inputs, {'RangeFrom': '2022.03.01 00:41', 'RangeTo': '2022.03.01 00:51'});

    // Click the first candle, then the last.
    await t.tap(find.byKey(const ValueKey('vp-tool')));
    await t.pump();
    await t.tapAt(posOf(t, lab, 60));
    await t.pump();
    expect(tool.clicking, isTrue);
    expect(find.text('Volume profile · click the last candle'), findsOneWidget);
    await t.tapAt(posOf(t, lab, 64));
    await t.pump();
    expect(ind.instances.last.inputs, {'RangeFrom': '2022.03.01 01:00', 'RangeTo': '2022.03.01 01:05'});
    expect(ind.instances, hasLength(3));

    // Esc mid-drawing cancels it; a second Esc drops the tool. Nothing is added.
    await t.tap(find.byKey(const ValueKey('vp-tool')));
    await t.pump();
    await t.tapAt(posOf(t, lab, 70));
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pump();
    expect(tool.clicking, isFalse);
    expect(tool.active, isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pump();
    expect(tool.active, isFalse);
    expect(ind.instances, hasLength(3));

    // Without the tool a drag pans the chart and draws nothing.
    await drag(t, posOf(t, lab, 80), posOf(t, lab, 90));
    expect(ind.instances, hasLength(3));
    expect(t.takeException(), isNull);
    await t.pump(const Duration(seconds: 1)); // the debounced settings save
  });

  testWidgets('resize by an edge, select by a click, Delete removes', (t) async {
    final (lab, m) = await pumpLab(t);
    final tool = lab.vpTool, ind = lab.indicators;
    m.onStart = (job) => m.finish(job);
    // 00:10 .. 00:30: the fake output's marker "mk" (00:19 @ 100.2) is inside, so the profile has a box.
    final i = ind.addProfile(at(10), at(31));
    await settle(t, () => i.state == 'ok' && i.output != null);
    await t.pump();
    final sp = tool.spans().single;
    expect((sp.first, sp.last), (10, 30));
    expect(sp.box, isNotNull);

    // The right edge, at the box's height: resize cursor, then drag it to bar 50 → RangeTo 00:51.
    final g = geo(t, lab);
    final edge = posOf(t, lab, 30, price: 100.2, dx: g.xs / 2);
    final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: edge);
    await mouse.moveTo(edge);
    await t.pump();
    expect(tool.hoverEdge, (i, false));
    await mouse.removePointer();
    await drag(t, edge, posOf(t, lab, 50, price: 100.2));
    expect(i.inputs, {'RangeFrom': '2022.03.01 00:10', 'RangeTo': '2022.03.01 00:51'});
    expect(m.starts, hasLength(2), reason: 'recomputed by the engine for the new range');
    expect(ind.instances, [i], reason: 'resized, not added');
    await settle(t, () => i.state == 'ok' && i.output != null);
    await t.pump();

    // The left edge can't cross the right one: dragged past it, the range is its last bar.
    await drag(t, posOf(t, lab, 10, price: 100.2, dx: -g.xs / 2), posOf(t, lab, 70, price: 100.2));
    expect(i.inputs, {'RangeFrom': '2022.03.01 00:50', 'RangeTo': '2022.03.01 00:51'});
    await settle(t, () => i.state == 'ok' && i.output != null);
    ind.setProfileRange(i, at(10), at(31));
    await settle(t, () => i.state == 'ok' && i.output != null);
    await t.pump();

    // A click elsewhere deselects; a click inside the profile's box selects it; Delete removes it.
    // (A trade under the click wins: trade #1's line crosses this box, so the trades layer goes off.)
    lab.chart.toggleLayer('trades');
    await t.tapAt(posOf(t, lab, 100, price: 100.2));
    await t.pump();
    expect(tool.selected, isNull);
    await t.tapAt(posOf(t, lab, 20, price: 100.2));
    await t.pump();
    expect(tool.selected, i);
    await t.sendKeyEvent(LogicalKeyboardKey.delete);
    await t.pump();
    expect(ind.instances, isEmpty);
    expect(lab.settings.indicators, isEmpty);
    expect(t.takeException(), isNull);
    await t.pump(const Duration(seconds: 1)); // the debounced settings save
  });

  testWidgets('replay: a range ends at the cursor at the latest (no future)', (t) async {
    final (lab, m) = await pumpLab(t);
    final s = lab.chart;
    s.enterReplay();
    s.startAt(60);
    await t.pump();
    await t.tap(find.byKey(const ValueKey('vp-tool')));
    await t.pump();
    await drag(t, posOf(t, lab, 50), posOf(t, lab, 90));
    expect(lab.indicators.instances.single.inputs, {'RangeFrom': '2022.03.01 00:50', 'RangeTo': '2022.03.01 01:01'});
    expect(m.starts, hasLength(1));
    expect(t.takeException(), isNull);
    await t.pump(const Duration(seconds: 1)); // the debounced settings save
  });

  testWidgets('volume_profile not built yet: built first, then computed', (t) async {
    final (lab, m) = await pumpLab(t, status: 'not_built');
    final ind = lab.indicators;
    await t.tap(find.byKey(const ValueKey('vp-tool')));
    await t.pump();
    await drag(t, posOf(t, lab, 20), posOf(t, lab, 30));
    final i = ind.instances.single;
    await t.pump();
    expect(i.state, 'unbuilt');
    expect(i.status, 'Not built yet: computed after its build');
    expect(m.builds, ['volume_profile']);
    expect(m.starts, isEmpty, reason: 'no job for a plugin that does not exist yet');
    m.onStart = (job) => m.finish(job);
    m.status = {'volume_profile': 'built'};
    m.engine.emit({'event': 'build_finished', 'build_id': 'build-1', 'ok': true, 'status': 'ok'});
    await settle(t, () => i.state == 'ok');
    expect(m.starts.single['inputs'], {'RangeFrom': '2022.03.01 00:20', 'RangeTo': '2022.03.01 00:31'});
    await t.pump(const Duration(seconds: 1)); // the debounced settings save
  });
}

