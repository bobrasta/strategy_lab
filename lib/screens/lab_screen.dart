import 'package:flutter/material.dart';

import '../chart/price_chart.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/chart_overlays.dart';
import '../widgets/common.dart';
import '../widgets/events_drawer.dart';
import '../widgets/left_rail.dart';
import '../widgets/stats_drawer.dart';
import '../widgets/top_bar.dart';

/// The chart is the app: rail, top bar and handle are thin; drawers and the
/// expanded rail overlay the chart and never resize it.
class LabScreen extends StatelessWidget {
  const LabScreen({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: state,
        builder: (context, _) {
          final s = state, chrome = !s.focus;
          return Scaffold(
            backgroundColor: C.bg,
            body: Padding(
              padding: const EdgeInsets.all(8),
              child: Stack(children: [
                Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (chrome) ...[SizedBox(width: 56, child: CollapsedRail(state: s)), const SizedBox(width: 8)],
                  Expanded(child: LayoutBuilder(builder: (context, c) => _main(s, chrome, c.maxHeight))),
                ]),
                if (chrome && s.leftOpen) ...[
                  Positioned.fill(child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => s.toggleLeft(false))),
                  Positioned(left: 0, top: 0, bottom: 0, width: 268, child: ExpandedRail(state: s)),
                ],
              ]),
            ),
          );
        },
      );

  Widget _main(AppState s, bool chrome, double h) {
    final drawerH = h * 0.35;
    final bottomOpen = chrome && s.bottomOpen && s.eventsLoaded;
    final rightOpen = chrome && s.rightOpen && s.eventsLoaded;
    final dockBottom = bottomOpen ? drawerH + 16 : (chrome ? 64.0 : 20.0);
    final centreRight = rightOpen ? 388.0 : 0.0;
    final pendingEv = s.isReplay && s.peek != null ? s.eventById(s.pending) : null;

    return Stack(children: [
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (chrome) ...[TopBar(state: s), const SizedBox(height: 8)],
        Expanded(child: _chartPanel(s, chrome, rightOpen)),
        if (chrome && !bottomOpen) ...[const SizedBox(height: 8), EventsHandle(state: s)],
      ]),
      if (rightOpen) Positioned(right: 0, top: 56, bottom: bottomOpen ? drawerH + 8 : 48, width: 380, child: StatsDrawer(state: s)),
      if (bottomOpen) Positioned(left: 0, right: 0, bottom: 0, height: drawerH, child: EventsDrawer(state: s)),
      if (s.isReplay && s.loaded) Positioned(left: 0, right: centreRight, bottom: dockBottom, child: Center(child: ReplayDock(state: s))),
      if (pendingEv != null)
        Positioned(left: 0, right: centreRight, bottom: dockBottom + 68, child: Center(child: PredictPrompt(state: s, ev: pendingEv))),
    ]);
  }

  Widget _chartPanel(AppState s, bool chrome, bool rightOpen) {
    final sel = s.selectedEvent;
    final showDetail = chrome && !s.isReplay && sel != null;
    final hasMsg = s.error != null || s.notice != null;
    return Container(
      decoration: BoxDecoration(color: C.bg, borderRadius: BorderRadius.circular(16), border: Border.all(color: C.line)),
      clipBehavior: Clip.antiAlias,
      child: Stack(children: [
        if (!s.loaded)
          Positioned.fill(child: EmptyState(state: s))
        else ...[
          Positioned.fill(child: PriceChart(state: s)),
          Positioned(
            left: 16,
            top: 14,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              IgnorePointer(child: OhlcReadout(state: s)),
              if (s.isReplay) ...[const SizedBox(height: 10), ReplayCounters(state: s)],
            ]),
          ),
          Positioned(top: 12, right: rightOpen ? 392 : 12, child: ChartToolbar(state: s)),
          if (s.isReplay) Positioned(top: 12, left: 0, right: 0, child: Center(child: ReplayTools(state: s))),
          if (s.drill != null && !hasMsg)
            Positioned(
              top: 60,
              left: 0,
              right: 0,
              child: Center(
                child: Glass(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  child: Text('M1 drill-down · ${s.eventsTf} candle boundaries shown · Esc to return', style: ts(12, color: C.mute)),
                ),
              ),
            ),
          if (showDetail) Positioned(left: 16, bottom: 16, width: 380, child: EventDetailCard(state: s, ev: sel)),
          if (s.focus)
            Positioned(
              left: 16,
              bottom: 40,
              child: Glass(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Text('Focus mode · press F to exit', style: ts(12, color: C.mute)),
              ),
            ),
        ],
        if (hasMsg) Positioned(top: s.isReplay ? 104 : 60, left: 0, right: 0, child: Center(child: MessageBanner(state: s))),
      ]),
    );
  }
}
