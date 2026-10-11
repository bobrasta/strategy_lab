// The volume profile tool against the real engine: on the data file's chart (no run), pick the tool,
// drag across 40 M15 candles with the mouse, and the engine's volume_profile indicator computes the
// profile for exactly that range; every object lies inside the selected candles' time and price span.
// Then resize it by its right edge (recomputed), and Delete removes it. Run with a new empty
// SETTINGS_DIR:
//   flutter test integration_test/volume_profile_tool_test.dart -d linux --dart-define=SETTINGS_DIR=/tmp/sl-vp
import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:strategy_lab/chart/chart_geometry.dart';
import 'package:strategy_lab/chart/price_chart.dart';
import 'package:strategy_lab/indicators/input_time.dart';
import 'package:strategy_lab/main.dart';
import 'package:strategy_lab/state/lab_state.dart';

const settingsDir = String.fromEnvironment('SETTINGS_DIR');

Future<void> waitFor(WidgetTester t, bool Function() ok, String what, {Duration limit = const Duration(minutes: 3)}) async {
  final sw = Stopwatch()..start();
  while (!ok()) {
    if (sw.elapsed > limit) fail('timed out waiting for $what');
    await t.pump(const Duration(milliseconds: 200));
  }
}

ChartGeometry geo(WidgetTester t, LabState lab) =>
    ChartGeometry.compute(t.getSize(find.byType(PriceChart)), lab.chart, lab.chart.candles!, lab.chart.visibleCursor, 0);

Offset posOf(WidgetTester t, LabState lab, int bar, {double? price, double dx = 0}) {
  final g = geo(t, lab);
  return t.getTopLeft(find.byType(PriceChart)) + Offset(g.x(bar) + dx, price == null ? (g.top + g.bottom) / 2 : g.y(price));
}

Future<void> drag(WidgetTester t, Offset from, Offset to) async {
  final gst = await t.startGesture(from, kind: PointerDeviceKind.mouse);
  for (var k = 1; k <= 12; k++) {
    await gst.moveTo(Offset.lerp(from, to, k / 12)!);
    await t.pump(const Duration(milliseconds: 16));
  }
  await gst.up();
  await t.pump();
}

Future<Set<String>> hummerPids() async =>
    '${(await Process.run('pgrep', ['hummer'])).stdout}'.split('\n').where((l) => l.trim().isNotEmpty).toSet();

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('volume profile tool: drag candle to candle → engine profile of that range; resize; delete', (t) async {
    expect(settingsDir, isNotEmpty, reason: 'run with --dart-define=SETTINGS_DIR=<new empty dir>');
    final before = await hummerPids();
    final LabState lab = await createLab(settingsDir: settingsDir);
    final s = lab.chart, ind = lab.indicators, tool = lab.vpTool;
    await t.pumpWidget(StrategyLabApp(lab: lab));
    await lab.init();
    await waitFor(t, () => lab.engine.ready && ind.listed, 'engine ready');
    if (!s.loaded) {
      await lab.openDataChart();
      await waitFor(t, () => s.loaded && lab.opening == null, 'data chart');
    }
    expect(s.timeframe, 'M15');
    await t.pumpAndSettle();
    final c = s.candles!;
    // 40 bars ending 30 bars before the last one, all on screen.
    final last = s.n - 31, first = last - 39;
    expect(first, greaterThanOrEqualTo(s.viewStart));

    await t.tap(find.byKey(const ValueKey('vp-tool')));
    await t.pump();
    await drag(t, posOf(t, lab, first), posOf(t, lab, last));
    final i = ind.instances.single;
    final from = c.t[first], to = c.t[last] + 15 * 60000;
    expect(i.inputs, {'RangeFrom': fmtInputTime(from), 'RangeTo': fmtInputTime(to)});
    await waitFor(t, () => i.state == 'ok' && i.output != null, 'profile computed (${i.status})');

    // The engine's run used exactly that range, and every object lies inside the selected candles.
    final manifest = jsonDecode(File('${i.out}/indicator.json').readAsStringSync()) as Map;
    expect(manifest['result'], 'ok');
    expect((manifest['indicator'] as Map)['inputs'], i.inputs);
    var lo = double.infinity, hi = -double.infinity;
    for (var k = first; k <= last; k++) {
      lo = c.l[k] < lo ? c.l[k] : lo;
      hi = c.h[k] > hi ? c.h[k] : hi;
    }
    final objs = i.output!.drawings.objectsAt(s.nowMs, from, to);
    expect(objs.map((o) => o.name), containsAll(['vp_poc', 'vp_vah', 'vp_val']));
    expect(objs.where((o) => o.kind == 'zone').length, greaterThan(10), reason: 'volume rows');
    for (final o in objs) {
      expect(o.t1, greaterThanOrEqualTo(from), reason: o.name);
      expect(o.t2, isNotNull);
      expect(o.t2!, lessThanOrEqualTo(to), reason: o.name);
      for (final p in [o.p1, o.p2]) {
        expect(p, inInclusiveRange(lo - 1e-9, hi + 1e-9), reason: '${o.name} price inside the range high/low');
      }
    }
    final sp = tool.spans().single;
    expect((sp.first, sp.last), (first, last));
    expect(tool.selected, i);
    await t.pumpAndSettle();

    // Resize: the right edge, dragged 10 bars to the right → recomputed for the longer range.
    final oldOut = i.out;
    final g = geo(t, lab), y = (sp.box!.$1 + sp.box!.$2) / 2;
    await drag(t, posOf(t, lab, last, price: y, dx: g.xs / 2), posOf(t, lab, last + 10, price: y));
    expect(i.inputs['RangeTo'], fmtInputTime(c.t[last + 10] + 15 * 60000));
    await waitFor(t, () => i.state == 'ok' && i.output != null, 'resized profile computed');
    expect(i.out, isNot(oldOut));
    expect(tool.spans().single.last, last + 10);

    // Delete removes it (selected since it was drawn and resized).
    expect(tool.selected, i);
    await t.sendKeyEvent(LogicalKeyboardKey.delete);
    await t.pump();
    expect(ind.instances, isEmpty);

    await lab.shutdown();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    // No hummer process of ours is left, orphans included (another Strategy Lab may be open with its
    // own engine, so the ones running before the test don't count).
    expect((await hummerPids()).difference(before), isEmpty, reason: 'engine or worker left running');
  }, timeout: const Timeout(Duration(minutes: 6)));
}
