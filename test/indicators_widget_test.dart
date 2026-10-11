import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strategy_lab/main.dart';
import 'package:strategy_lab/state/app_state.dart';
import 'package:strategy_lab/state/lab_state.dart';

import 'support.dart';

/// Alternates real time (isolate parsing) and pumps (events and futures of the test zone) until
/// [cond] holds.
Future<void> settle(WidgetTester t, bool Function() cond) async {
  for (var k = 0; k < 500 && !cond(); k++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await t.pump();
  }
  expect(cond(), isTrue, reason: 'timed out');
}

Future<(LabState, M7Engine)> pumpWithEngine(WidgetTester t, Size size, {bool supported = true, bool withRun = true}) async {
  await loadAppFont();
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  late LabState lab;
  final m = M7Engine(supported: supported);
  await t.runAsync(() async {
    lab = await testLab(engine: m.engine);
    await lab.indicators.refresh();
    if (withRun) await openFakeRun(writeFakeRun(), into: lab.chart);
  });
  await t.pumpWidget(StrategyLabApp(lab: lab, manageEngine: false));
  await t.pump(const Duration(milliseconds: 50));
  return (lab, m);
}

void main() {
  for (final size in const [Size(1440, 900), Size(1920, 1037)]) {
    final tag = '${size.width.toInt()}×${size.height.toInt()}';

    testWidgets('Indicators panel: list, Add → form → chart, failed instance, Layers rail, replay at $tag', (t) async {
      final (lab, m) = await pumpWithEngine(t, size);
      final ind = lab.indicators;
      await t.tap(find.byKey(const ValueKey('indicators-button')));
      await t.pump();
      expect(find.byKey(const ValueKey('indicators-panel')), findsOneWidget);
      expect(find.text('Strategy Tester'), findsNothing, reason: 'the drawer shows one panel at a time');
      for (final n in ['band', 'fvg', 'donchian']) {
        expect(find.text(n), findsOneWidget);
      }
      expect(find.text('stale: rebuild'), findsOneWidget);

      // Add → the inputs form (schema from indicator_inputs) → Add to chart.
      m.onStart = (job) => m.finish(job);
      await t.tap(find.byKey(const ValueKey('indicator-add-band')));
      await settle(t, () => ind.schemaOf('band') != null);
      await t.pump();
      expect(find.text('Add band to the chart'), findsOneWidget);
      expect(find.text('Middle'), findsOneWidget, reason: 'the declared plots are listed');
      expect(t.takeException(), isNull);
      await t.tap(find.byKey(const ValueKey('indicator-apply')));
      await settle(t, () => ind.instances.isNotEmpty && ind.instances.first.state == 'ok');
      await t.pump();
      expect(find.text('133 plot values · 4 objects'), findsOneWidget);

      // A second instance that fails: error and tails in the panel.
      m.onStart = (job) => m.finish(job, status: 'failed', extra: {'error': 'OnInit failed', 'journal_tail': ['[2022-03-01 00:00:00] Period too small'], 'stderr_tail': []});
      ind.add('band', const {'Period': '2'});
      await settle(t, () => ind.instances.last.state == 'failed');
      await t.pump();
      expect(find.text('band (2)'), findsOneWidget);
      expect(find.text('Failed: OnInit failed · exit code 1'), findsOneWidget);
      expect(find.textContaining('Period too small'), findsOneWidget);

      // Edit inputs from the panel opens the form on that instance.
      await t.tap(find.byKey(ValueKey('indicator-edit-${ind.instances.first.uid}')));
      await t.pump();
      expect(find.text('Inputs · band'), findsOneWidget);
      expect(find.text('Apply'), findsOneWidget);
      expect(t.takeException(), isNull);

      // The Layers rail lists both, with show/hide.
      lab.chart.toggleLeft(true);
      await t.pump();
      expect(find.byKey(ValueKey('rail-indicator-${ind.instances.first.uid}')), findsOneWidget);
      expect(find.text('2 indicators'), findsOneWidget);
      lab.chart.toggleLeft(false);

      // Replay with the indicator drawn: the chart paints at several cursors without errors.
      lab.chart.enterReplay();
      for (final bar in [0, 15, 42, 60, 70, 119]) {
        lab.chart.startAt(bar);
        await t.pump();
      }
      lab.chart.exitReplay();
      await t.pump(const Duration(seconds: 1)); // the debounced settings save
      expect(t.takeException(), isNull);
    });

    testWidgets('an engine without indicator support shows the message and nothing else at $tag', (t) async {
      final (lab, _) = await pumpWithEngine(t, size, supported: false);
      lab.chart.toggleIndicators(true);
      await t.pump();
      expect(find.byKey(const ValueKey('indicators-unsupported')), findsOneWidget);
      expect(find.textContaining('This engine has no indicator support'), findsOneWidget);
      expect(find.text('Build engine'), findsOneWidget);
      expect(find.text('On the chart'), findsNothing);
      // The rest of the app is unaffected: the Tester still opens.
      lab.chart.toggleRight(true);
      await t.pump();
      expect(find.text('Strategy Tester'), findsOneWidget);
      expect(lab.chart.rightPanel, RightPanel.tester);
      expect(t.takeException(), isNull);
    });

    testWidgets('without a chart the panel offers to open the data file at $tag', (t) async {
      final (lab, _) = await pumpWithEngine(t, size, withRun: false);
      lab.chart.toggleIndicators(true);
      await t.pump();
      expect(find.byKey(const ValueKey('indicators-open-chart')), findsOneWidget);
      expect(find.text('Open chart'), findsWidgets, reason: 'in the panel and in the empty chart');
      expect(t.takeException(), isNull);
    });
  }
}
