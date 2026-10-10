// M6 B acceptance, driven in the real app against the real engine (`hummer serve` and its workers):
//   1. engine starts; build fvg_continuation; run it on 2021-01-01 .. 2023-12-31 (CLAUDE.md rule 10);
//      the run opens; replay one of its trades.
//   2. extending To past 2023 makes Start show the protected-period dialog; Cancel starts nothing.
//   3. after closing, no `hummer` process is left.
// restart_test.dart then starts a new app process on the same settings and reopens the run from History.
// Results are only checked for presence (run ok, trades exist), never printed.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:strategy_lab/main.dart';
import 'package:strategy_lab/state/app_state.dart';
import 'package:strategy_lab/state/lab_state.dart';

const settingsDir = String.fromEnvironment('SETTINGS_DIR');

/// Clicks the field (as a user would), then types.
Future<void> typeInto(WidgetTester t, String key, String text) async {
  final f = find.byKey(ValueKey(key));
  await t.ensureVisible(f);
  await t.tap(f);
  await t.pump();
  await t.enterText(f, text);
  await t.pump();
}

Future<void> waitFor(WidgetTester t, bool Function() ok, String what, {Duration limit = const Duration(minutes: 3)}) async {
  final sw = Stopwatch()..start();
  while (!ok()) {
    if (sw.elapsed > limit) fail('timed out waiting for $what');
    await t.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('build, run 2021–2023, replay a trade, protected-period dialog, clean exit', (t) async {
    expect(settingsDir, isNotEmpty, reason: 'run with --dart-define=SETTINGS_DIR=<scratch dir>');
    final LabState lab = await createLab(settingsDir: settingsDir);
    final s = lab.chart;
    await t.pumpWidget(StrategyLabApp(lab: lab));
    await lab.init();
    await waitFor(t, () => lab.engine.ready && lab.strategies.isNotEmpty, 'engine ready');

    // Tester → fvg_continuation → Build
    await t.tap(find.byKey(const ValueKey('tester-button')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('strategy-menu')));
    await t.pumpAndSettle();
    await t.tap(find.text('fvg_continuation').last);
    await t.pumpAndSettle();
    expect(lab.strategy, 'fvg_continuation');
    await t.tap(find.byKey(const ValueKey('build-strategy')));
    await waitFor(t, () => lab.build != null && !lab.build!.running, 'build');
    expect(lab.build!.status, 'ok', reason: lab.build!.lines.join('\n'));
    await waitFor(t, () => lab.strategyInfo?.status == 'built' && lab.schema != null, 'inputs after build');
    expect(lab.settings.inputs['fvg_continuation'] ?? const {}, isEmpty, reason: 'FVG defaults are never changed');

    // Dates 2021-01-01 .. 2023-12-31 → Start (no protected overlap, so no dialog)
    await typeInto(t, 'from-field', '2021-01-01');
    await typeInto(t, 'to-field', '2023-12-31');
    expect(lab.protectedOverlap(), isNull);
    await t.tap(find.byKey(const ValueKey('start-run')));
    await t.pump();
    expect(find.byKey(const ValueKey('protected-run-dialog')), findsNothing);
    await waitFor(t, () => lab.progress != null && !lab.progress!.active, 'run to finish', limit: const Duration(minutes: 5));
    expect(lab.progress!.state, 'ok', reason: '${lab.progress!.error}');
    await waitFor(t, () => s.run != null && s.run!.manifest.dir == lab.progress!.out, 'run to open');
    final run = s.run!;
    expect(run.manifest.from, '2021-01-01');
    expect(run.manifest.to, '2023-12-31');
    expect(run.manifest.inputs, isEmpty);
    expect(run.trades, isNotEmpty);
    expect(run.equity, isNotNull);
    expect(lab.isVisible(run.manifest), isTrue);
    expect(s.candles!.endMs(s.n - 1), lessThanOrEqualTo(DateTime.utc(2024).millisecondsSinceEpoch), reason: 'chart cut at the run end');

    // Trades tab → pick a trade → Replay trade → play a little
    s.showTab(ResultsTab.trades);
    await t.pumpAndSettle();
    final ticket = run.trades[run.trades.length ~/ 2].ticket;
    s.selectTrade(ticket, reveal: true);
    await t.pump();
    await t.tap(find.text('Replay trade'));
    await t.pump();
    expect(s.isReplay, isTrue);
    expect(s.selectedTrade, ticket);
    final entryBar = s.barOf(run.tradeByTicket(ticket)!.openMs);
    expect(s.visibleCursor, entryBar - 50);
    expect(run.positionAt(s.nowMs)?.ticket, isNot(ticket), reason: 'not open yet before its entry');
    // Play a moment (it moves), then step trade by trade onto the entry bar.
    s.togglePlay();
    final c0 = s.visibleCursor;
    await waitFor(t, () => s.visibleCursor > c0 + 3, 'replay to play', limit: const Duration(seconds: 20));
    s.togglePlay();
    if (s.visibleCursor > entryBar) s.startAt(entryBar - 50);
    for (var i = 0; i < 50 && s.visibleCursor < entryBar; i++) {
      s.nextTrade();
    }
    expect(s.visibleCursor, entryBar);
    await t.pump();
    final tr = run.tradeByTicket(ticket)!;
    expect(tr.openMs, lessThanOrEqualTo(s.nowMs), reason: 'the entry is inside the cursor bar');
    expect(run.positionAt(s.nowMs)?.ticket, tr.closeMs > s.nowMs ? ticket : isNot(ticket),
        reason: 'it is the position at the cursor unless it also closed inside that bar');
    expect(find.byKey(const ValueKey('readout-position')), findsOneWidget);
    expect(run.equityAt(s.nowMs)!.ms, lessThanOrEqualTo(s.nowMs));
    s.exitReplay();
    await t.pump();

    // Extend To past 2023 → Start → protected-period dialog → Cancel: nothing starts
    final runsBefore = lab.history.length;
    await typeInto(t, 'to-field', '2024-03-31');
    expect(lab.settings.to, '2024-03-31');
    expect(lab.protectedOverlap(), isNotNull);
    await t.tap(find.byKey(const ValueKey('start-run')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('protected-run-dialog')), findsOneWidget);
    expect(find.textContaining('2024-01-01 onwards'), findsWidgets);
    await t.tap(find.byKey(const ValueKey('protected-cancel')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('protected-run-dialog')), findsNothing);
    expect(lab.progress!.active, isFalse);
    await lab.refreshHistory();
    expect(lab.history.length, runsBefore, reason: 'Cancel started no run');
    // Leave the persisted dates on 2021–2023.
    await typeInto(t, 'to-field', '2023-12-31');
    expect(lab.settings.to, '2023-12-31');

    // Exit: shutdown → the service and any worker are gone.
    final engPid = lab.engine.pid!;
    await lab.shutdown();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final pg = await Process.run('pgrep', ['-a', 'hummer']);
    expect('${pg.stdout}'.trim(), isEmpty, reason: 'hummer processes left after exit (serve pid was $engPid)');
    File('$settingsDir/acceptance_run_dir.txt').writeAsStringSync(run.manifest.dir);
  }, timeout: const Timeout(Duration(minutes: 10)));
}
