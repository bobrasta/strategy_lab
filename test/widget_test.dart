import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strategy_lab/main.dart';
import 'package:strategy_lab/run/history.dart';
import 'package:strategy_lab/run/run_data.dart';
import 'package:strategy_lab/state/app_state.dart';
import 'package:strategy_lab/state/lab_state.dart';

import 'support.dart';

/// A runs folder with: an ma_cross run, a 2021–2024 fvg_continuation run (unconfirmed: protected)
/// and a 2021–2023 fvg_continuation run.
Future<List<RunManifest>> runsFolder() async {
  final root = tempDir(), runs = Directory('${root.path}/runs')..createSync();
  for (final (name, key, from, to) in [
    ('r1', 'ma_cross', '2022-03-01', '2022-03-01'),
    ('r2', 'fvg_continuation', '2021-01-01', '2024-06-30'),
    ('r3', 'fvg_continuation', '2021-01-01', '2023-12-31'),
  ]) {
    final run = writeFakeRun(strategyKey: key, from: from, to: to, dir: Directory('${root.path}/$name')..createSync());
    final f = File('${run.path}/run.json');
    final j = jsonDecode(f.readAsStringSync()) as Map;
    (j['range'] as Map)['first_simulated_bar'] = '$from 00:00:00';
    (j['range'] as Map)['last_simulated_bar'] = '$to 23:59:00';
    (j['summary'] as Map)['net_profit'] = name == 'r2' ? 4242.42 : 10.0;
    f.writeAsStringSync(jsonEncode(j));
    run.renameSync('${runs.path}/$name');
  }
  return scanRuns(runs.path);
}

Future<LabState> pumpApp(WidgetTester t, Size size, {bool withRun = true}) async {
  await loadFallbackFont();
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  late LabState lab;
  await t.runAsync(() async {
    lab = await testLab();
    lab.history = await runsFolder();
    if (withRun) await openFakeRun(writeFakeRun(), into: lab.chart);
  });
  await t.pumpWidget(StrategyLabApp(lab: lab, manageEngine: false));
  await t.pump(const Duration(milliseconds: 50));
  return lab;
}

void main() {
  for (final size in const [Size(1440, 900), Size(1920, 1037)]) {
    final tag = '${size.width.toInt()}×${size.height.toInt()}';
    testWidgets('empty app renders at $tag', (t) async {
      final lab = await pumpApp(t, size, withRun: false);
      expect(find.textContaining('Start a backtest in the Tester'), findsOneWidget);
      lab.chart.toggleRight(true);
      lab.chart.toggleLeft(true);
      await t.pump();
      expect(t.takeException(), isNull);
      expect(find.text('Strategy Tester'), findsOneWidget);
      expect(find.text('The strategy list comes from the engine, which is not ready.'), findsOneWidget);
    });

    testWidgets('a run renders: tester, every results tab, replay, rail at $tag', (t) async {
      final lab = await pumpApp(t, size);
      final s = lab.chart;
      expect(find.text('fake'), findsWidgets);
      s.toggleRight(true);
      for (final tab in ResultsTab.values) {
        s.showTab(tab);
        await t.pump();
        expect(t.takeException(), isNull, reason: '$tab');
      }
      s.toggleTall();
      s.showTab(ResultsTab.trades);
      await t.pump();
      expect(find.text('2 trades'), findsOneWidget);
      s.enterReplay();
      s.startAt(20);
      await t.pump();
      expect(find.text('1 trades opened so far'), findsOneWidget);
      expect(find.text('Buy 0.1 @ 100.120'), findsOneWidget, reason: 'position readout at the cursor');
      s.showTab(ResultsTab.backtest);
      await t.pump();
      expect(find.textContaining('hidden during replay'), findsOneWidget);
      s.toggleLeft(true);
      await t.pump();
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('history masks an unconfirmed protected run; compare shows two runs side by side', (t) async {
    final lab = await pumpApp(t, const Size(1920, 1037));
    lab.chart.showTab(ResultsTab.history);
    await t.pump();
    expect(find.text('Protected'), findsOneWidget);
    expect(find.textContaining('4,242'), findsNothing, reason: 'the protected net profit is never shown');
    final visible = lab.history.where(lab.isVisible).toList();
    expect(visible, hasLength(2));
    for (final m in visible) {
      lab.toggleCompare(m);
    }
    await t.runAsync(lab.openCompare);
    await t.pump();
    expect(find.text('Compare runs'), findsOneWidget);
    expect(find.text('Deposit / leverage'), findsOneWidget);
    expect(t.takeException(), isNull);
    lab.closeCompare();
    await t.pump();
    expect(find.text('Compare runs'), findsNothing);
  });
}
