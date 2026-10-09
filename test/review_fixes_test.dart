import 'package:backy/chart/chart_layer.dart';
import 'package:backy/chart/fvg_layer.dart';
import 'package:backy/main.dart';
import 'package:backy/state/app_state.dart';
import 'package:backy/widgets/top_bar.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'no_lookahead_test.dart' as nl;
import 'support.dart';

LayerContext ctx(AppState s) => LayerContext(state: s, candles: s.candles!, cursor: s.visibleCursor, pulse: 0);

Future<AppState> pumpApp(WidgetTester t, {Size size = const Size(1920, 1037), int preset = 2}) async {
  await loadFallbackFont();
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final s = AppState()..applyPreset(preset);
  await t.pumpWidget(FvgLabApp(state: s));
  await t.pump();
  return s;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('zone labels and emphasis', () {
    test('labels and "Selected only" start off', () {
      final s = AppState();
      expect(s.layersOn, isNot(contains('labels')));
      expect(s.layersOn, isNot(contains('selected')));
    });

    test('label text follows the replay cursor: Waiting → Open · wick → Bounce · wick 0.40', () async {
      final s = await nl.load();
      final z = s.zones.single;
      s.enterReplay();
      s.startAt(nl.touch - 1);
      expect(FvgLayer.zoneLabel(z, ctx(s)), 'Waiting');
      s.step(1);
      expect(FvgLayer.zoneLabel(z, ctx(s)), startsWith('Open · wick '));
      while (s.visibleCursor < nl.end) {
        s.step(1);
      }
      expect(FvgLayer.zoneLabel(z, ctx(s)), 'Bounce · wick 0.40');
    });

    test('"Selected only" draws just the selected zone (all zones while nothing is selected)', () {
      final s = AppState()..applyPreset(1);
      expect(s.zones.length, greaterThan(1));
      s.toggleLayer('selected');
      expect(s.zones.every((z) => FvgLayer.drawn(z, ctx(s))), isTrue);
      final pick = s.zones[1];
      s.select(pick.ev.id);
      expect(s.zones.where((z) => FvgLayer.drawn(z, ctx(s))), [pick]);
      expect(FvgLayer.isSelected(pick, ctx(s)), isTrue);
      expect(FvgLayer.dimmed, closeTo(0.35, 1e-9));
    });

    testWidgets('chart toolbar has a "Selected only" toggle', (t) async {
      final s = await pumpApp(t);
      await t.tap(find.text('Selected only'));
      await t.pump();
      expect(s.layersOn, contains('selected'));
    });
  });

  group('top bar', () {
    testWidgets('fits at 1920 px without scrolling; condition filters live in the Filters popover', (t) async {
      final s = await pumpApp(t);
      final bar = find.byType(TopBar);
      final scroll = t.state<ScrollableState>(find.descendant(of: bar, matching: find.byType(Scrollable)).first);
      expect(scroll.position.maxScrollExtent, 0, reason: 'nothing hidden at 1920 px');
      for (final keep in ['Explore', 'Replay', 'Scenario', 'Direction', 'Stats', 'Focus', 'Reload study', 'M15']) {
        expect(find.descendant(of: bar, matching: find.text(keep)), findsOneWidget, reason: keep);
      }
      for (final k in kConditionFilters) {
        expect(find.descendant(of: bar, matching: find.text(k)), findsNothing, reason: '$k moved to the popover');
      }

      await t.tap(find.byKey(const ValueKey('filters-button')));
      await t.pump();
      expect(find.text('Conditions'), findsOneWidget);
      for (final k in ['Displacement', 'Formation session', 'Touch session', 'HTF trend', 'Age', 'Sweep', 'Period']) {
        expect(find.text(k), findsOneWidget, reason: k);
      }
      expect(find.text('49+'), findsOneWidget, reason: 'Age buckets');
      expect(find.text('Hold-out 2026'), findsOneWidget, reason: 'Period options');

      await t.tap(find.text('D4 strong'));
      await t.pump();
      expect(s.filters['Displacement'], 4);
      expect(s.activeConditionFilters, 1);
      await t.tap(find.text('Yes'));
      await t.pump();
      expect(s.filters['Sweep'], 1);
      expect(find.descendant(of: find.byKey(const ValueKey('filters-button')), matching: find.text('2')), findsOneWidget, reason: 'count badge');

      await t.tap(find.text('Reset conditions'));
      await t.pump();
      expect(s.activeConditionFilters, 0);
      await t.tapAt(const Offset(900, 600)); // outside the popover closes it
      await t.pump();
      expect(find.text('Conditions'), findsNothing);
    });

    testWidgets('"Asia formation (candidate)" preset exists and sets Formation session = Asia', (t) async {
      final s = await pumpApp(t);
      await t.tap(find.text('Presets'));
      await t.pumpAndSettle();
      await t.tap(find.text('Asia formation (candidate)'));
      await t.pumpAndSettle();
      expect(s.filters['Formation session'], 1);
      expect(s.activeConditionFilters, 1);
    });

    testWidgets('hold-out lock: Period = Hold-out shows the locked panel', (t) async {
      final s = await pumpApp(t);
      expect(s.holdoutLocked, isTrue);
      if (!s.rightOpen) s.toggleRight();
      s.setFilter('Period', 3);
      await t.pump();
      expect(s.statsLocked, isTrue);
      expect(find.text('Hold-out 2026 is locked'), findsOneWidget);
    });
  });
}
