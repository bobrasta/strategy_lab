import 'package:flutter/material.dart';

import '../chart/price_chart.dart';
import '../state/lab_state.dart';
import '../theme.dart';
import '../widgets/chart_overlays.dart';
import '../widgets/common.dart';
import '../widgets/compare_view.dart';
import '../widgets/left_rail.dart';
import '../widgets/results_drawer.dart';
import '../widgets/tester_panel.dart';
import '../widgets/top_bar.dart';

/// The chart is the app: rail, top bar and handle are thin; the Tester (right), the Results
/// (bottom) and the expanded rail overlay the chart and never resize it.
class LabScreen extends StatelessWidget {
  const LabScreen({super.key, required this.lab});
  final LabState lab;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([lab, lab.chart]),
        builder: (context, _) {
          final s = lab.chart, chrome = !s.focus;
          return Scaffold(
            backgroundColor: C.bg,
            body: Padding(
              padding: const EdgeInsets.all(8),
              child: Stack(children: [
                Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (chrome) ...[SizedBox(width: 56, child: CollapsedRail(lab: lab)), const SizedBox(width: 8)],
                  Expanded(child: LayoutBuilder(builder: (context, c) => _main(chrome, c.maxHeight))),
                ]),
                if (chrome && s.leftOpen) ...[
                  Positioned.fill(child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => s.toggleLeft(false))),
                  Positioned(left: 0, top: 0, bottom: 0, width: 300, child: ExpandedRail(lab: lab)),
                ],
              ]),
            ),
          );
        },
      );

  Widget _main(bool chrome, double h) {
    final s = lab.chart;
    final drawerH = h * (s.bottomTall ? 0.62 : 0.38);
    final bottomOpen = chrome && s.bottomOpen;
    final rightOpen = chrome && s.rightOpen;
    final dockBottom = bottomOpen ? drawerH + 16 : (chrome ? 64.0 : 20.0);
    final centreRight = rightOpen ? 408.0 : 0.0;
    final cmp = lab.compare;

    return Stack(children: [
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (chrome) ...[TopBar(lab: lab), const SizedBox(height: 8)],
        Expanded(child: _chartPanel(chrome, rightOpen)),
        if (chrome && !bottomOpen) ...[const SizedBox(height: 8), ResultsHandle(lab: lab)],
      ]),
      if (rightOpen) Positioned(right: 0, top: 56, bottom: bottomOpen ? drawerH + 8 : 48, width: 400, child: TesterPanel(lab: lab)),
      if (bottomOpen) Positioned(left: 0, right: 0, bottom: 0, height: drawerH, child: ResultsDrawer(lab: lab)),
      if (s.isReplay && s.loaded && cmp == null) ...[
        Positioned(left: 0, right: centreRight, bottom: dockBottom, child: Center(child: ReplayDock(state: s))),
        // Above the dock, clear of the readouts (top left) and the chart toolbar (top right).
        Positioned(left: 0, right: centreRight, bottom: dockBottom + 64, child: Center(child: ReplayTools(state: s))),
      ],
      if (cmp != null) Positioned(left: 24, right: 24, top: chrome ? 72 : 16, bottom: 24, child: CompareView(lab: lab, data: cmp)),
    ]);
  }

  Widget _chartPanel(bool chrome, bool rightOpen) {
    final s = lab.chart;
    final hasMsg = s.error != null || s.notice != null;
    return Container(
      decoration: BoxDecoration(color: C.bg, borderRadius: BorderRadius.circular(16), border: Border.all(color: C.line)),
      clipBehavior: Clip.antiAlias,
      child: Stack(children: [
        if (!s.loaded)
          Positioned.fill(child: EmptyState(lab: lab))
        else ...[
          Positioned.fill(child: PriceChart(state: s)),
          Positioned(
            left: 16,
            top: 14,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              IgnorePointer(child: OhlcReadout(state: s)),
              if (s.run != null) ...[const SizedBox(height: 10), IgnorePointer(child: RunReadout(state: s))],
            ]),
          ),
          Positioned(top: 12, right: rightOpen ? 412 : 12, child: ChartToolbar(state: s)),
          if (lab.opening != null || s.busy != null)
            Positioned(
              bottom: 64,
              left: 0,
              right: 0,
              child: Center(
                child: Glass(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  child: Text(lab.opening ?? s.busy!, style: ts(12, color: C.mute)),
                ),
              ),
            ),
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
