// M7 acceptance (SPEC §14 row 7), driven in the real app against the real engine (`hummer serve`,
// `hummer indicator` workers, the engine's indicators/ programs):
//   1. Indicators panel → Open chart (the Tester's data file, no run) → Build donchian.
//   2. Add donchian with an input changed in the form → computed by the engine → drawn in Explore.
//   3. Replay: nothing stamped after the cursor is shown, and nothing at all before the first stamp.
//   4. fvg (objects): added with defaults, zones only as of the cursor.
//   5. Edit donchian's inputs → recomputed in a new folder; Remove fvg; re-adding the same donchian
//      is a cache hit (same folder, no worker).
//   6. After closing, no `hummer` process is left.
// indicators_restart_test.dart then starts a new app process on the same settings: the attached
// indicators come back and are served from the engine's cache.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:strategy_lab/indicators/indicators_state.dart';
import 'package:strategy_lab/main.dart';
import 'package:strategy_lab/state/app_state.dart';
import 'package:strategy_lab/state/lab_state.dart';
import 'package:strategy_lab/widgets/input_form.dart';

const settingsDir = String.fromEnvironment('SETTINGS_DIR');

Future<void> waitFor(WidgetTester t, bool Function() ok, String what, {Duration limit = const Duration(minutes: 3)}) async {
  final sw = Stopwatch()..start();
  while (!ok()) {
    if (sw.elapsed > limit) fail('timed out waiting for $what');
    await t.pump(const Duration(milliseconds: 200));
  }
}

/// Scrolls the widget with [key] into view, then taps it (the drawer scrolls).
Future<void> tapKey(WidgetTester t, Key key) async {
  final f = find.byKey(key);
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
}

/// Types into the inputs form's field for [name], as a user would.
Future<void> setInput(WidgetTester t, String name, String text) async {
  final f = find.descendant(
    of: find.byWidgetPredicate((w) => w is InputRow && w.spec.name == name),
    matching: find.byType(EditableText),
  );
  await t.ensureVisible(f);
  await t.tap(f);
  await t.pump();
  await t.enterText(f, text);
  await t.pump();
}

Future<void> buildIndicator(WidgetTester t, LabState lab, String name) async {
  await tapKey(t, ValueKey('indicator-build-$name'));
  await waitFor(t, () => lab.build != null && lab.build!.name == name && !lab.build!.running, 'build $name');
  expect(lab.build!.status, 'ok', reason: lab.build!.lines.join('\n'));
  expect(lab.build!.kind, 'indicator');
  await waitFor(t, () => lab.indicators.infoOf(name)?.status == 'built', '$name listed as built');
  // back to the panel (a build opens the Build tab)
  lab.chart.showTab(ResultsTab.backtest);
  await t.pumpAndSettle();
}

Future<IndicatorInstance> addFromForm(WidgetTester t, LabState lab, String name, Map<String, String> inputs) async {
  final ind = lab.indicators;
  final before = ind.instances.length;
  await tapKey(t, ValueKey('indicator-add-$name'));
  await waitFor(t, () => ind.draft?.name == name && ind.schemaOf(name) != null, '$name inputs form');
  await t.pumpAndSettle();
  for (final e in inputs.entries) {
    await setInput(t, e.key, e.value);
  }
  expect(ind.draftProblems(), isEmpty);
  await tapKey(t, const ValueKey('indicator-apply'));
  await t.pump();
  expect(ind.instances.length, before + 1);
  final i = ind.instances.last;
  await waitFor(t, () => i.state == 'ok' && i.output != null, '$name computed (${i.status})');
  return i;
}

/// The display rule in replay: every plot point shown at `now` is stamped at or before it.
void expectNoPlotAfterNow(AppState s, IndicatorInstance i) {
  final now = s.nowMs, from = s.candles!.time(0).millisecondsSinceEpoch;
  for (final ser in i.output!.series.values) {
    for (final k in ser.visible(from, now, now)) {
      expect(ser.stamp[k], lessThanOrEqualTo(now), reason: 'plot record stamped after the cursor');
      expect(ser.time[k], lessThan(now), reason: 'a bar not yet opened');
    }
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('indicators: build, add with inputs, Explore, Replay, edit, remove, cache hit, clean exit', (t) async {
    expect(settingsDir, isNotEmpty, reason: 'run with --dart-define=SETTINGS_DIR=<scratch dir>');
    final LabState lab = await createLab(settingsDir: settingsDir);
    final s = lab.chart, ind = lab.indicators;
    await t.pumpWidget(StrategyLabApp(lab: lab));
    await lab.init();
    await waitFor(t, () => lab.engine.ready && ind.listed, 'engine ready, indicators listed');
    expect(ind.unsupported, isNull);
    expect(ind.list.map((x) => x.name), containsAll(['consolidation', 'donchian', 'fvg', 'volume_profile']));

    // 1. Indicators panel → Open chart (no run) → Build donchian
    await t.tap(find.byKey(const ValueKey('indicators-button')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('indicators-panel')), findsOneWidget);
    if (!s.loaded) {
      await t.tap(find.byKey(const ValueKey('indicators-open-chart')));
      await waitFor(t, () => s.loaded && lab.opening == null, 'chart of the data file');
    }
    expect(s.run, isNull);
    expect(s.candlesPath, lab.settings.dataFile);
    await buildIndicator(t, lab, 'donchian');

    // 2. Add donchian, Period 30 in the form → engine → layer
    final dc = await addFromForm(t, lab, 'donchian', {'Period': '30'});
    expect(dc.inputs, {'Period': '30'});
    expect(dc.label, 'donchian (30)');
    expect(dc.output!.plots.map((p) => p.name), ['Upper', 'Lower', 'Middle']);
    expect(dc.output!.plotRecords, greaterThan(1000));
    expect(dc.out, contains('/runs/indicators/donchian_'));
    expect(File('${dc.out}/indicator.json').existsSync(), isTrue);
    expect(s.indicatorLayers, contains(dc.layer));
    // Explore: now = the end of the chart; the channel has a value at the last completed H1 bar.
    expect(s.isReplay, isFalse);
    await t.pumpAndSettle();
    final upper = dc.output!.series[0]!;
    expect(upper.valueAt(upper.time[upper.length - 1], s.nowMs), isNotNull);

    // 3. Replay: before the first stamp nothing; later only what was stamped by then.
    s.enterReplay();
    final firstStamp = upper.stamp.reduce((a, b) => a < b ? a : b);
    s.startAt(s.barOf(firstStamp) - 5);
    await t.pump();
    expect(s.nowMs, lessThan(firstStamp));
    for (final ser in dc.output!.series.values) {
      expect(ser.visible(s.candles!.time(0).millisecondsSinceEpoch, s.nowMs, s.nowMs), isEmpty);
    }
    s.startAt(s.n ~/ 2);
    await t.pump();
    expectNoPlotAfterNow(s, dc);
    expect(upper.visible(s.candles!.time(0).millisecondsSinceEpoch, s.nowMs, s.nowMs), isNotEmpty);
    s.togglePlay();
    final c0 = s.visibleCursor;
    await waitFor(t, () => s.visibleCursor > c0 + 3, 'replay to play', limit: const Duration(seconds: 20));
    s.togglePlay();
    expectNoPlotAfterNow(s, dc);
    s.exitReplay();
    await t.pump();

    // 4. fvg: objects (zones), as of the cursor in replay
    await buildIndicator(t, lab, 'fvg');
    final fvg = await addFromForm(t, lab, 'fvg', const {});
    expect(fvg.label, 'fvg');
    final zones = fvg.output!.drawings;
    expect(zones.lives, greaterThan(100));
    final end = s.nowMs, start = s.candles!.time(0).millisecondsSinceEpoch;
    final atEnd = zones.objectsAt(end, start, end).length;
    expect(atEnd, greaterThan(0));
    s.enterReplay();
    s.startAt(s.n ~/ 3);
    await t.pump();
    final early = zones.objectsAt(s.nowMs, start, s.nowMs);
    for (final o in early) {
      expect(o.t1, lessThanOrEqualTo(s.nowMs), reason: 'an object anchored after the cursor');
    }
    s.startAt(0);
    await t.pump();
    expect(zones.objectsAt(s.nowMs, start, s.nowMs), isEmpty, reason: 'nothing before the first stamp');
    s.exitReplay();
    await t.pumpAndSettle();

    // 5a. Edit donchian's inputs → a new computation in another folder, new label
    final oldOut = dc.out;
    await tapKey(t, ValueKey('indicator-edit-${dc.uid}'));
    await waitFor(t, () => ind.draft?.instance == dc, 'edit form');
    await t.pumpAndSettle();
    await setInput(t, 'Period', '25');
    await tapKey(t, const ValueKey('indicator-apply'));
    await t.pump();
    expect(dc.label, 'donchian (25)');
    await waitFor(t, () => dc.state == 'ok' && dc.output != null, 'donchian recomputed');
    expect(dc.out, isNot(oldOut));
    expect(dc.inputs, {'Period': '25'});

    // 5b. Remove fvg
    await t.ensureVisible(find.byKey(ValueKey('indicator-remove-${fvg.uid}')));
    await t.tap(find.byKey(ValueKey('indicator-remove-${fvg.uid}')));
    await t.pumpAndSettle();
    expect(ind.instances, isNot(contains(fvg)));
    expect(s.indicatorLayers, isNot(contains(fvg.layer)));
    expect(lab.settings.indicators.map((x) => x.name), ['donchian']);

    // 5c. Re-adding the same donchian (Period 25) is a cache hit: same folder, answered without a worker.
    final again = await addFromForm(t, lab, 'donchian', {'Period': '25'});
    expect(again.cached, isTrue);
    expect(again.out, dc.out);
    expect(again.status, contains('cached'));
    await t.ensureVisible(find.byKey(ValueKey('indicator-remove-${again.uid}')));
    await t.tap(find.byKey(ValueKey('indicator-remove-${again.uid}')));
    await t.pumpAndSettle();
    expect(lab.settings.indicators.map((x) => x.name), ['donchian']);

    // For the restart test.
    File('$settingsDir/indicators_out.txt').writeAsStringSync(dc.out!);

    // 6. Clean exit
    await lab.shutdown();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect('${(await Process.run('pgrep', ['-a', 'hummer'])).stdout}'.trim(), isEmpty);
  }, timeout: const Timeout(Duration(minutes: 10)));
}
