// Second process of the acceptance: same settings folder as acceptance_test.dart. The run made there
// is listed in History after the restart, opens without re-running, and replays.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:strategy_lab/main.dart';
import 'package:strategy_lab/state/app_state.dart';

const settingsDir = String.fromEnvironment('SETTINGS_DIR');

Future<void> waitFor(WidgetTester t, bool Function() ok, String what, {Duration limit = const Duration(minutes: 2)}) async {
  final sw = Stopwatch()..start();
  while (!ok()) {
    if (sw.elapsed > limit) fail('timed out waiting for $what');
    await t.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('after a restart: settings remembered, the run reopens from History and replays', (t) async {
    final dir = File('$settingsDir/acceptance_run_dir.txt').readAsStringSync().trim();
    final lab = await createLab(settingsDir: settingsDir);
    final s = lab.chart;
    // Remembered between sessions.
    expect(lab.settings.lastStrategy, 'fvg_continuation');
    expect([lab.settings.from, lab.settings.to], ['2021-01-01', '2023-12-31']);
    expect(lab.settings.lastRunDir, dir);
    await t.pumpWidget(StrategyLabApp(lab: lab));
    await lab.init();
    await waitFor(t, () => lab.engine.ready && lab.history.any((h) => h.dir == dir), 'engine and history');
    // The last run is restored on start; close it, then reopen it from the History tab by hand.
    await waitFor(t, () => lab.opening == null && s.run != null, 'last run restored');
    s.closeRun();
    s.showTab(ResultsTab.history);
    await t.pumpAndSettle();
    final m = lab.history.firstWhere((h) => h.dir == dir);
    expect(lab.isVisible(m), isTrue);
    await t.tap(find.text(m.runId).first);
    await waitFor(t, () => s.run?.manifest.dir == dir, 'run to reopen from History');
    expect(lab.progress, isNull, reason: 'reopened from files; nothing was re-run');
    s.showTab(ResultsTab.backtest);
    await t.pumpAndSettle();
    expect(find.text('Total net profit'), findsOneWidget);
    final tr = s.run!.trades.first;
    s.replayTrade(tr.ticket);
    await t.pump();
    expect(s.isReplay, isTrue);
    final entry = s.barOf(tr.openMs);
    for (var i = 0; i < 20 && s.visibleCursor < entry; i++) {
      s.nextTrade(); // may stop at an earlier trade's exit first
    }
    expect(s.visibleCursor, entry);
    await t.pump();
    await lab.shutdown();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect('${(await Process.run('pgrep', ['-a', 'hummer'])).stdout}'.trim(), isEmpty);
  }, timeout: const Timeout(Duration(minutes: 6)));
}
