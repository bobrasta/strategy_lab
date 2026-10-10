// SPEC §14 M6 checks on ma_cross (full data): no UI stall while a full run executes and opens
// (largest gap between 16 ms timer ticks on the UI isolate), and kill -9 of a worker mid-run gives
// "Run failed" while the next run works. The runs this test creates are deleted at the end.
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:strategy_lab/main.dart';
import 'package:strategy_lab/state/app_state.dart';

const settingsDir = String.fromEnvironment('SETTINGS_DIR');

Future<void> waitFor(WidgetTester t, bool Function() ok, String what, {Duration limit = const Duration(minutes: 3)}) async {
  final sw = Stopwatch()..start();
  while (!ok()) {
    if (sw.elapsed > limit) fail('timed out waiting for $what');
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('full ma_cross run without UI stalls; kill -9 of a worker → Run failed, next run works', (t) async {
    final lab = await createLab(settingsDir: '$settingsDir/engine_test');
    final s = lab.chart;
    final made = <String>[];
    await t.pumpWidget(StrategyLabApp(lab: lab));
    await lab.init();
    await waitFor(t, () => lab.engine.ready && lab.strategies.isNotEmpty, 'engine');
    lab.selectStrategy('ma_cross');
    await waitFor(t, () => lab.schema != null, 'inputs');
    lab.set((x) => x
      ..from = ''
      ..to = '');

    // 1. A full 2021-01 → 2026-10 run with per-M1 equity, then opened (graph tab showing).
    var worst = Duration.zero, worstAt = Duration.zero;
    final sw = Stopwatch()..start();
    var last = sw.elapsed;
    final marks = <String>[];
    void mark(String what) => marks.add('${sw.elapsedMilliseconds} ms $what');
    final tick = Timer.periodic(const Duration(milliseconds: 16), (_) {
      final now = sw.elapsed, gap = now - last;
      if (gap > worst) {
        worst = gap;
        worstAt = now;
      }
      if (gap.inMilliseconds > 60) mark('gap ${gap.inMilliseconds} ms (state ${lab.progress?.state}, opening ${lab.opening != null}, run ${s.run != null})');
      last = now;
    });
    s.toggleBottom(true);
    s.showTab(ResultsTab.graph);
    mark('start');
    await lab.startRun();
    mark('started');
    made.add(lab.progress!.out);
    await waitFor(t, () => lab.progress != null && !lab.progress!.active, 'full run');
    mark('finished');
    expect(lab.progress!.state, 'ok');
    await waitFor(t, () => s.run?.manifest.dir == lab.progress!.out, 'full run to open');
    mark('opened');
    await t.pump(const Duration(milliseconds: 300));
    mark('pumped');
    s.enterReplay();
    s.startAt(s.n ~/ 2);
    await t.pump(const Duration(milliseconds: 300));
    tick.cancel();
    final runSecs = sw.elapsed.inMilliseconds / 1000;
    binding.reportData = {'worst_ui_gap_ms': worst.inMilliseconds, 'run_and_open_s': runSecs};
    // ignore: avoid_print
    print('full ma_cross run + open: ${runSecs.toStringAsFixed(1)} s; worst UI event-loop gap ${worst.inMilliseconds} ms; '
        'equity rows ${s.run!.equity!.index.rows}; worst at ${worstAt.inMilliseconds} ms\n${marks.join('\n')}');
    // Profile mode (flutter drive --profile, like the installed app) measures ~65 ms; debug adds JIT warm-up.
    expect(worst.inMilliseconds, lessThan(const bool.fromEnvironment('dart.vm.product') || kProfileMode ? 120 : 400),
        reason: 'the UI isolate must never block on the run or its files');
    s.exitReplay();

    // 2. kill -9 the worker mid-run.
    await lab.startRun();
    final out = lab.progress!.out;
    made.add(out);
    await waitFor(t, () => lab.progress!.pct > 5, 'run progress');
    final pids = (await Process.run('pgrep', ['-f', 'hummer run .*$out'])).stdout.toString().trim().split('\n');
    expect(pids.first, isNotEmpty);
    await Process.run('kill', ['-9', ...pids]);
    await waitFor(t, () => !lab.progress!.active, 'failed run');
    expect(lab.progress!.state, 'failed');
    expect(lab.progress!.signal, 'SIGKILL');
    expect(s.error, startsWith('Run failed'));
    await t.pump();
    expect(find.textContaining('Run failed'), findsWidgets);

    // 3. The next run works.
    lab.set((x) => x
      ..from = '2021-01-04'
      ..to = '2021-03-31');
    await lab.startRun();
    made.add(lab.progress!.out);
    await waitFor(t, () => !lab.progress!.active, 'short run');
    expect(lab.progress!.state, 'ok');

    await lab.shutdown();
    for (final d in made) {
      if (Directory(d).existsSync()) Directory(d).deleteSync(recursive: true);
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect('${(await Process.run('pgrep', ['-a', 'hummer'])).stdout}'.trim(), isEmpty);
  }, timeout: const Timeout(Duration(minutes: 8)));
}
