import 'dart:ui';

import 'package:strategy_lab/chart/chart_geometry.dart';
import 'package:strategy_lab/chart/price_chart.dart';
import 'package:strategy_lab/main.dart';
import 'package:strategy_lab/state/app_state.dart';
import 'package:strategy_lab/state/lab_state.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// The app with a fake run open on M1 (120 bars, so the view starts zoomed in) and no engine.
Future<AppState> pumpChart(WidgetTester t, {bool replay = false}) async {
  await loadFallbackFont();
  t.view.physicalSize = const Size(1440, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  late LabState lab;
  await t.runAsync(() async {
    lab = await testLab();
    await openFakeRun(writeFakeRun(), into: lab.chart);
  });
  final s = lab.chart;
  s.zoomBy(0.4);
  if (replay) {
    s.enterReplay();
    s.startAt(70);
  }
  await t.pumpWidget(StrategyLabApp(lab: lab, manageEngine: false));
  await t.pump();
  return s;
}

Rect chartRect(WidgetTester t) => t.getRect(find.byType(PriceChart));

/// A point inside the plot (left of the price axis).
Offset plotPoint(WidgetTester t, double fx, double fy) {
  final r = chartRect(t);
  return Offset(r.left + (r.width - ChartGeometry.axisRight) * fx, r.top + r.height * fy);
}

/// A point on the price axis.
Offset axisPoint(WidgetTester t) {
  final r = chartRect(t);
  return Offset(r.right - ChartGeometry.axisRight / 2, r.center.dy);
}

void main() {
  testWidgets('mouse drag left/right scrolls through time', (t) async {
    final s = await pumpChart(t);
    s.pan(-30);
    s.pan(30);
    final v0 = s.viewStart;
    await t.dragFrom(plotPoint(t, 0.5, 0.5), const Offset(300, 0));
    expect(s.viewStart, lessThan(v0), reason: 'dragging right shows earlier bars');
    final v1 = s.viewStart;
    await t.dragFrom(plotPoint(t, 0.5, 0.5), const Offset(-150, 0));
    expect(s.viewStart, greaterThan(v1));
    expect(s.priceZoom, 1);
  });

  testWidgets('mouse drag up/down moves the price view; Fit resets it', (t) async {
    final s = await pumpChart(t);
    await t.dragFrom(plotPoint(t, 0.5, 0.5), const Offset(0, 120));
    expect(s.priceShift, greaterThan(0));
    s.fit();
    expect(s.priceManual, isFalse);
  });

  testWidgets('dragging the price axis changes candle height; double-click resets', (t) async {
    final s = await pumpChart(t);
    await t.dragFrom(axisPoint(t), const Offset(0, -100));
    expect(s.priceZoom, greaterThan(1.5), reason: 'drag up = taller candles');
    await t.dragFrom(axisPoint(t), const Offset(0, 200));
    expect(s.priceZoom, lessThan(1), reason: 'drag down = shorter candles');
    expect(s.viewStart, isNot(0), reason: 'axis drag does not scroll time');
    await t.tapAt(axisPoint(t));
    await t.pump(const Duration(milliseconds: 100));
    await t.tapAt(axisPoint(t));
    expect(s.priceManual, isFalse);
  });

  testWidgets('mouse wheel zooms around the pointer; Shift+wheel scrolls', (t) async {
    final s = await pumpChart(t);
    final p = plotPoint(t, 0.5, 0.5);
    final g0 = ChartGeometry.compute(const Size(1, 1), s, s.candles!, s.visibleCursor, 0);
    final z0 = g0.zoom;
    await t.sendEventToBinding(PointerScrollEvent(position: p, scrollDelta: const Offset(0, 200)));
    expect(s.zoom, greaterThan(z0), reason: 'wheel down = zoom out');
    final z1 = s.zoom;
    await t.sendEventToBinding(PointerScrollEvent(position: p, scrollDelta: const Offset(0, -200)));
    expect(s.zoom, lessThan(z1), reason: 'wheel up = zoom in');

  });

  testWidgets('touchpad: two fingers up/down zoom, left/right scroll (axis locked per swipe)', (t) async {
    final s = await pumpChart(t);
    final p = plotPoint(t, 0.6, 0.5);
    final pad = TestPointer(7, PointerDeviceKind.trackpad);

    Future<void> swipe(Offset total) async {
      await t.sendEventToBinding(pad.panZoomStart(p));
      for (var i = 1; i <= 10; i++) {
        await t.sendEventToBinding(pad.panZoomUpdate(p, pan: total * (i / 10)));
      }
      await t.sendEventToBinding(pad.panZoomEnd());
      await t.pump();
    }

    await swipe(const Offset(0, 120));
    final z0 = s.zoom;
    await swipe(const Offset(0, -60));
    expect(s.zoom, lessThan(z0), reason: 'fingers up = zoom in');
    final z = s.zoom, v = s.viewStart;
    await swipe(const Offset(250, 6)); // mostly right with a little vertical wobble
    expect(s.zoom, z, reason: 'a sideways swipe must not zoom');
    expect(s.viewStart, lessThan(v), reason: 'fingers right = earlier bars');
    await swipe(const Offset(0, 160));
    expect(s.zoom, greaterThan(z), reason: 'fingers down = zoom out');
    expect(s.priceManual, isFalse, reason: 'two-finger gestures never drag the price');
  });

  testWidgets('replay: panning right of the cursor shows nothing new', (t) async {
    final s = await pumpChart(t, replay: true);
    final cur = s.visibleCursor;
    await t.dragFrom(plotPoint(t, 0.5, 0.5), const Offset(-600, 0));
    expect(s.visibleCursor, cur);
    final g = ChartGeometry.compute(const Size(1200, 700), s, s.candles!, s.visibleCursor, 0);
    var hiKnown = -double.infinity;
    for (var i = 0; i <= cur; i++) {
      if (s.candles!.h[i] > hiKnown) hiKnown = s.candles!.h[i];
    }
    expect(g.hi, lessThanOrEqualTo(hiKnown + (hiKnown - g.lo)), reason: 'scale built from bars ≤ cursor only');
  });
}
