import 'dart:ui';

import 'package:backy/chart/chart_geometry.dart';
import 'package:backy/chart/price_chart.dart';
import 'package:backy/main.dart';
import 'package:backy/state/app_state.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Future<AppState> pumpChart(WidgetTester t, {int preset = 1}) async {
  await loadFallbackFont();
  t.view.physicalSize = const Size(1440, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final s = AppState()..applyPreset(preset);
  await t.pumpWidget(FvgLabApp(state: s));
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
    final barUnder = (s.viewStart + 0.5 * (s.zoom + ChartGeometry.rightPadBars)).round();
    expect(g0.zoom, 150);
    await t.sendEventToBinding(PointerScrollEvent(position: p, scrollDelta: const Offset(0, -200)));
    expect(s.zoom, lessThan(150), reason: 'wheel up = zoom in');
    expect((s.viewStart + 0.5 * (s.zoom + ChartGeometry.rightPadBars)).round(), closeTo(barUnder, 1), reason: 'bar under the pointer stays put');
    final z = s.zoom;
    await t.sendEventToBinding(PointerScrollEvent(position: p, scrollDelta: const Offset(0, 400)));
    expect(s.zoom, greaterThan(z));
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

    await swipe(const Offset(0, -120));
    expect(s.zoom, lessThan(150), reason: 'fingers up = zoom in');
    final z = s.zoom, v = s.viewStart;
    await swipe(const Offset(250, 6)); // mostly right with a little vertical wobble
    expect(s.zoom, z, reason: 'a sideways swipe must not zoom');
    expect(s.viewStart, lessThan(v), reason: 'fingers right = earlier bars');
    await swipe(const Offset(0, 160));
    expect(s.zoom, greaterThan(z), reason: 'fingers down = zoom out');
    expect(s.priceManual, isFalse, reason: 'two-finger gestures never drag the price');
  });

  testWidgets('replay: panning right of the cursor shows nothing new', (t) async {
    final s = await pumpChart(t, preset: 3);
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
