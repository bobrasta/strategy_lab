// M8 acceptance, first process (SPEC §14 row 8), in the real app against the real engine:
//   1. Practice panel: a start date in 2024 asks first (protected period); Cancel starts nothing.
//   2. Start on 2023-03-06: the chart opens in replay just before it, nothing later painted; trading
//      waits for the first step.
//   3. Market buy 0.10 with SL/TP from the panel: filled on the next tick by the engine.
//   4. A buy limit below the price; drag the position's SL line on the chart: modified by the engine.
//   5. Play until the position exits; step back: trading disabled; Back to latest.
//   6. Pause; then the app closes with no `hummer` process of ours left.
// practice_restart_test.dart resumes the saved session in a new process and finishes it.
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:strategy_lab/chart/chart_geometry.dart';
import 'package:strategy_lab/chart/price_chart.dart';
import 'package:strategy_lab/main.dart';
import 'package:strategy_lab/state/lab_state.dart';

const settingsDir = String.fromEnvironment('SETTINGS_DIR');

Future<void> waitFor(WidgetTester t, bool Function() ok, String what, {Duration limit = const Duration(minutes: 2)}) async {
  final sw = Stopwatch()..start();
  while (!ok()) {
    if (sw.elapsed > limit) fail('timed out waiting for $what');
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> tapKey(WidgetTester t, String key) async {
  final f = find.byKey(ValueKey(key));
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pump();
}

Future<void> typeKey(WidgetTester t, String key, String text) async {
  final f = find.byKey(ValueKey(key));
  await t.ensureVisible(f);
  await t.tap(f);
  await t.pump();
  await t.enterText(f, text);
  await t.pump();
}

Future<Set<String>> hummerPids() async =>
    '${(await Process.run('pgrep', ['hummer'])).stdout}'.split('\n').where((l) => l.trim().isNotEmpty).toSet();

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('practice: protected start asks, trade by hand, drag SL, exit, step back, pause', (t) async {
    expect(settingsDir, isNotEmpty, reason: 'run with --dart-define=SETTINGS_DIR=<new empty dir>');
    final before = await hummerPids();
    final LabState lab = await createLab(settingsDir: settingsDir);
    final s = lab.chart, p = lab.practice;
    await t.pumpWidget(StrategyLabApp(lab: lab));
    await lab.init();
    await waitFor(t, () => lab.engine.ready, 'engine ready');
    await tapKey(t, 'practice-button');
    expect(find.byKey(const ValueKey('practice-panel')), findsOneWidget);

    // 1. 2024 is protected for practice by default: the dialog, then Cancel.
    await typeKey(t, 'practice-date', '2024-02-05');
    await tapKey(t, 'practice-start');
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('practice-protected-dialog')), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(p.sessionId, isNull);

    // 2. Start on Mon 2023-03-06.
    await typeKey(t, 'practice-date', '2023-03-06');
    await tapKey(t, 'practice-start');
    await waitFor(t, () => p.active && s.loaded && !p.busy, 'session ready');
    final startMs = DateTime.utc(2023, 3, 6).millisecondsSinceEpoch;
    expect(s.isReplay, isTrue);
    expect(s.practiceLock, isTrue);
    expect(s.nowMs, lessThan(startMs), reason: 'nothing of the start date is shown yet');
    expect(p.engineMs, isNull);
    expect(p.canTrade, isFalse);
    s.exitReplay(); // refused while practising
    await t.pump();
    expect(s.isReplay, isTrue);
    for (var k = 0; k < 41 && (p.engineMs == null || s.nowMs < startMs + 10 * 3600000); k++) {
      s.step(1);
      await waitFor(t, () => !p.busy, 'advance');
    }
    expect(p.engineMs, isNotNull);
    expect(p.engineMs!, lessThanOrEqualTo(s.nowMs), reason: 'the engine never runs past the cursor by advancing');
    expect(p.canTrade, isTrue);

    // 3. Market buy 0.10, SL/TP 4.000 away from the cursor bar's close.
    final c = s.candles!;
    final close = c.c[s.visibleCursor];
    final sl = (close - 4).toStringAsFixed(3), tp = (close + 4).toStringAsFixed(3);
    await typeKey(t, 'practice-size', '0.10');
    await typeKey(t, 'practice-sl', sl);
    await typeKey(t, 'practice-tp', tp);
    final nowBefore = s.nowMs;
    await tapKey(t, 'practice-buy');
    await waitFor(t, () => p.position != null || p.message != null, 'the buy');
    expect(p.message, isNull, reason: p.message);
    final pos = p.position!;
    expect(pos.volume, 0.1);
    expect(pos.sl.toStringAsFixed(3), sl);
    expect(pos.openMs, greaterThan(nowBefore), reason: 'filled on the next tick, after what was seen');
    expect(pos.openMs - nowBefore, lessThanOrEqualTo(3 * 24 * 3600000), reason: 'the very next tick (weekend at most)');
    await t.pumpAndSettle();
    expect(find.byKey(ValueKey('practice-position-${pos.ticket}')), findsOneWidget);

    // 4. A buy limit 8.000 below, then drag the position's SL line 1.000 lower on the chart.
    await t.tap(find.text('Limit'));
    await t.pump();
    await typeKey(t, 'practice-price', (close - 8).toStringAsFixed(3));
    await typeKey(t, 'practice-sl', '');
    await typeKey(t, 'practice-tp', '');
    await tapKey(t, 'practice-buy');
    await waitFor(t, () => p.orders.isNotEmpty || p.message != null, 'the buy limit');
    expect(p.message, isNull, reason: p.message);
    expect(p.orders.single.type, 'buy_limit');
    await t.pumpAndSettle();
    final chart = find.byType(PriceChart);
    final g = ChartGeometry.compute(t.getSize(chart), s, s.candles!, s.visibleCursor, 0);
    final origin = t.getTopLeft(chart);
    final from = origin + Offset(g.plotW * 0.5, g.y(pos.sl)), to = origin + Offset(g.plotW * 0.5, g.y(pos.sl - 1));
    final gst = await t.startGesture(from, kind: PointerDeviceKind.mouse);
    for (var k = 1; k <= 8; k++) {
      await gst.moveTo(Offset.lerp(from, to, k / 8)!);
      await t.pump();
    }
    await gst.up();
    await waitFor(t, () => !p.busy && p.position != null && p.position!.sl < pos.sl - 0.5, 'the SL modified by a drag');
    expect(p.journal.last, contains('modify position #${pos.ticket}'));

    // 5. Play until the position exits (SL or TP), then step back: looking only.
    s.setSpeed(50);
    s.togglePlay();
    await waitFor(t, () => p.position == null && !p.busy, 'the exit', limit: const Duration(minutes: 3));
    if (s.playing) s.togglePlay();
    await waitFor(t, () => !p.busy, 'idle');
    expect(p.trades, isNotEmpty);
    expect(p.trades.first.ticket, pos.ticket);
    s.step(-5);
    await t.pumpAndSettle();
    expect(p.atHead, isFalse);
    expect(p.canTrade, isFalse);
    expect(find.byKey(const ValueKey('practice-looking-back')), findsOneWidget);
    await tapKey(t, 'practice-back-to-latest');
    await t.pumpAndSettle();
    expect(p.atHead, isTrue);

    // 6. Pause: resumable, the chart free again.
    final out = p.out!, reached = p.reachedMs, trades = p.trades.length;
    await tapKey(t, 'practice-pause');
    await waitFor(t, () => p.sessionId == null, 'paused');
    expect(s.practiceLock, isFalse);
    expect(p.saved!['out'], out);
    expect(p.saved!['reached_ms'], reached);
    expect(File('$out/actions.jsonl').readAsLinesSync().length, greaterThanOrEqualTo(3));
    File('$settingsDir/practice_expect.txt').writeAsStringSync('$out\n$reached\n$trades\n');

    await lab.shutdown();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect((await hummerPids()).difference(before), isEmpty, reason: 'engine or worker left running');
  }, timeout: const Timeout(Duration(minutes: 8)));
}
