import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../state/lab_state.dart';
import '../theme.dart';
import 'build_view.dart';
import 'common.dart';
import 'graph_view.dart';
import 'history_view.dart';
import 'report.dart';
import 'tables.dart';

String tabLabel(ResultsTab t) => switch (t) {
      ResultsTab.backtest => 'Backtest',
      ResultsTab.graph => 'Graph',
      ResultsTab.trades => 'Trades',
      ResultsTab.deals => 'Deals',
      ResultsTab.journal => 'Journal',
      ResultsTab.history => 'History',
      ResultsTab.build => 'Build',
    };

/// Collapsed: a thin bar under the chart that opens the results.
class ResultsHandle extends StatelessWidget {
  const ResultsHandle({super.key, required this.lab});
  final LabState lab;

  @override
  Widget build(BuildContext context) {
    final s = lab.chart, m = s.run?.manifest;
    return GestureDetector(
      onVerticalDragUpdate: (d) {
        if (d.delta.dy < -4) s.toggleBottom(true);
      },
      child: HoverBox(
        onTap: () => s.toggleBottom(true),
        builder: (context, h) => Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(color: C.panel, borderRadius: BorderRadius.circular(16), border: Border.all(color: h ? C.lineHover : C.line)),
          child: Row(children: [
            Expanded(
              child: Row(children: [
                Text('Results', style: ts(13, w: FontWeight.w500)),
                const SizedBox(width: 8),
                Flexible(child: Text('·  ${m == null ? 'no run open' : m.runId}', overflow: TextOverflow.ellipsis, style: ts(13, color: C.mute))),
              ]),
            ),
            Container(width: 36, height: 4, decoration: BoxDecoration(color: C.line, borderRadius: BorderRadius.circular(999))),
            Expanded(
              child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                Text('Report, graph, trades, history', style: ts(12, color: C.mute)),
                const SizedBox(width: 6),
                const Icon(AppIcons.up, size: 14, color: C.mute),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// MT5-style tester tabs over the open run (and the run history / build output).
class ResultsDrawer extends StatelessWidget {
  const ResultsDrawer({super.key, required this.lab});
  final LabState lab;

  @override
  Widget build(BuildContext context) {
    final s = lab.chart;
    return Panel(
      shadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 48, offset: Offset(0, -16))],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          height: 50,
          child: Stack(children: [
            Positioned(
              top: 6,
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: () => s.toggleBottom(false),
                  onVerticalDragUpdate: (d) {
                    if (d.delta.dy > 4) s.toggleBottom(false);
                  },
                  child: Container(width: 36, height: 4, decoration: BoxDecoration(color: C.line, borderRadius: BorderRadius.circular(999))),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 12, right: 10, top: 6),
              child: Row(children: [
                Segmented<ResultsTab>(
                  values: ResultsTab.values,
                  selected: s.tab,
                  onChanged: s.showTab,
                  labelOf: tabLabel,
                  height: 26,
                  fontSize: 12,
                  padH: 12,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(s.run == null ? '' : s.run!.manifest.runId, overflow: TextOverflow.ellipsis, style: ts(12, color: C.mute)),
                ),
                RoundIconButton(
                  icon: s.bottomTall ? AppIcons.short : AppIcons.tall,
                  size: 30,
                  color: C.mute,
                  tooltip: s.bottomTall ? 'Shorter' : 'Taller',
                  onTap: s.toggleTall,
                ),
                RoundIconButton(icon: AppIcons.down, size: 30, color: C.mute, tooltip: 'Collapse', onTap: () => s.toggleBottom(false)),
              ]),
            ),
          ]),
        ),
        Expanded(child: _body(context)),
      ]),
    );
  }

  Widget _body(BuildContext context) {
    final s = lab.chart, run = s.run;
    switch (s.tab) {
      case ResultsTab.history:
        return HistoryView(lab: lab);
      case ResultsTab.build:
        return BuildView(lab: lab);
      default:
    }
    if (run == null) {
      return _Empty(lab.opening ?? 'No run open. Start one in the Tester, or open a past run from History.',
          action: lab.opening == null ? ('Open History', () => s.showTab(ResultsTab.history)) : null);
    }
    final replay = s.isReplay && !s.selectMode;
    return switch (s.tab) {
      ResultsTab.backtest => replay
          ? const _Empty('The report covers the whole run, so it is hidden during replay. Exit replay to see it.')
          : ReportView(manifest: run.manifest),
      ResultsTab.graph => run.equity == null
          ? _Empty(run.equityError ?? 'No equity file.')
          : Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: EquityGraph(series: [
                GraphSeries(store: run.equity!, label: '', equityColor: C.blue, balanceColor: C.text, cutMs: replay ? s.nowMs : null),
              ]),
            ),
      ResultsTab.trades => TradesTable(state: s),
      ResultsTab.deals => DealsTable(state: s),
      ResultsTab.journal => JournalView(state: s),
      _ => const SizedBox.shrink(),
    };
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.text, {this.action});
  final String text;
  final (String, VoidCallback)? action;
  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(text, textAlign: TextAlign.center, style: ts(13, color: C.mute)),
          if (action != null) ...[const SizedBox(height: 12), PillButton(label: action!.$1, onTap: action!.$2)],
        ]),
      );
}
