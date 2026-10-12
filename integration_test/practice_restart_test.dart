// M8 acceptance, second process: same settings folder as practice_test.dart. The paused session is
// offered for resume, comes back exactly where it was (the engine replays its actions.jsonl), steps on,
// and Finish turns it into a run that opens with its report and is listed in History.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:strategy_lab/main.dart';
import 'package:strategy_lab/state/app_state.dart';

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

Future<Set<String>> hummerPids() async =>
    '${(await Process.run('pgrep', ['hummer'])).stdout}'.split('\n').where((l) => l.trim().isNotEmpty).toSet();

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('practice after a restart: resume where it was, finish, the run in History', (t) async {
    final lines = File('$settingsDir/practice_expect.txt').readAsLinesSync();
    final out = lines[0], reached = int.parse(lines[1]), trades = int.parse(lines[2]);
    final before = await hummerPids();
    final lab = await createLab(settingsDir: settingsDir);
    final s = lab.chart, p = lab.practice;
    expect(lab.settings.practice?['out'], out);
    await t.pumpWidget(StrategyLabApp(lab: lab));
    await lab.init();
    await waitFor(t, () => lab.engine.ready, 'engine ready');
    await tapKey(t, 'practice-button');
    await tapKey(t, 'practice-resume');
    await waitFor(t, () => p.active && s.loaded && !p.busy, 'resumed');
    expect(p.out, out);
    expect(p.reachedMs, reached);
    expect(s.nowMs, lessThanOrEqualTo(reached), reason: 'back where it was, nothing later shown');
    expect(p.trades.length, trades, reason: 'the engine replayed the same requests');
    expect(p.atHead, isTrue);

    // A few bars on, then Finish.
    for (var k = 0; k < 4; k++) {
      s.step(1);
      await waitFor(t, () => !p.busy, 'advance');
    }
    expect(p.reachedMs, greaterThan(reached));
    await tapKey(t, 'practice-finish');
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('practice-finish-confirm')));
    await waitFor(t, () => s.run != null && s.run!.manifest.dir == out, 'the practice run opens', limit: const Duration(minutes: 1));
    expect(p.sessionId, isNull);
    expect(lab.settings.practice, isNull);
    expect(s.practiceLock, isFalse);
    final m = s.run!.manifest;
    expect(m.strategyKey, 'builtin:practice');
    expect(lab.isVisible(m), isTrue);
    expect(lab.history.any((h) => h.dir == out), isTrue);
    expect(s.run!.trades.length, greaterThanOrEqualTo(trades), reason: 'the engine\'s trades, as in trades.json');
    expect(File('$out/run.json').existsSync(), isTrue);
    s.showTab(ResultsTab.backtest);
    await t.pumpAndSettle();
    expect(find.text('Total net profit'), findsOneWidget);

    await lab.shutdown();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect((await hummerPids()).difference(before), isEmpty, reason: 'engine or worker left running');
    Directory(out).deleteSync(recursive: true); // a test session: not left in the user's History
  }, timeout: const Timeout(Duration(minutes: 6)));
}
