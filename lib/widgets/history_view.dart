import 'package:flutter/material.dart';

import '../run/run_data.dart';
import '../state/lab_state.dart';
import '../theme.dart';
import '../util/format.dart';
import 'common.dart';
import 'dialogs.dart';
import 'tables.dart';

/// Opens [m], asking first (and logging a confirmation) when its results are protected.
Future<void> openRunGuarded(BuildContext context, LabState lab, RunManifest m) async {
  var run = m;
  if (!lab.isVisible(m)) {
    final p = lab.protectionFor(m.strategyKey);
    if (p == null || !await confirmReveal(context, m, p)) return;
    final r = await lab.revealRun(m);
    if (r == null) return;
    run = r;
  }
  await lab.openRun(run);
}

String keyInputs(RunManifest m) => m.inputs.isEmpty ? 'defaults' : [for (final e in m.inputs.entries) '${e.key}=${e.value}'].join(', ');

class HistoryView extends StatelessWidget {
  const HistoryView({super.key, required this.lab});
  final LabState lab;

  static const cols = [
    Col('', 3),
    Col('Run at (UTC)', 10),
    Col('Strategy', 10),
    Col('Range', 13),
    Col('Key inputs', 16),
    Col('Trades', 5, right: true),
    Col('Net profit', 8, right: true),
    Col('Result', 6),
    Col('Folder', 14),
  ];

  @override
  Widget build(BuildContext context) {
    final h = lab.history, open = lab.chart.run?.manifest.dir;
    return Column(children: [
      SizedBox(
        height: 40,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(children: [
            Text('${fmtInt(h.length)} runs in ${lab.runsDir}', overflow: TextOverflow.ellipsis, style: ts(12, color: C.mute)),
            const Spacer(),
            if (lab.compareSel.isNotEmpty) ...[
              Text('${lab.compareSel.length} of 2 ticked', style: ts(12, color: C.mute)),
              const SizedBox(width: 8),
            ],
            PillButton(
              key: const ValueKey('compare-button'),
              label: 'Compare',
              icon: AppIcons.compare,
              height: 28,
              fontSize: 12,
              enabled: lab.compareSel.length == 2,
              onTap: lab.openCompare,
            ),
            const SizedBox(width: 6),
            PillButton(label: lab.historyLoading ? 'Reading…' : 'Refresh', icon: AppIcons.restart, height: 28, fontSize: 12, onTap: lab.refreshHistory),
          ]),
        ),
      ),
      Expanded(
        child: DataTableView(
          cols: cols,
          count: h.length,
          selected: (i) => h[i].dir == open,
          onTap: (i) => openRunGuarded(context, lab, h[i]),
          widgetCell: (i, j) {
            if (j != 0) return null;
            final m = h[i], on = lab.compareSel.contains(m.dir), vis = lab.isVisible(m);
            return RoundIconButton(
              icon: on ? Icons.check_box_outlined : Icons.check_box_outline_blank,
              size: 24,
              iconSize: 16,
              color: on ? C.gold : C.mute,
              enabled: vis && m.ok,
              tooltip: vis ? 'Compare' : 'Protected: open it to confirm first',
              onTap: () => lab.toggleCompare(m),
            );
          },
          cell: (i, j) {
            final m = h[i], vis = lab.isVisible(m);
            final span = m.simSpan;
            return switch (j) {
              0 => ('', null),
              1 => (fmtFull(DateTime.fromMillisecondsSinceEpoch(m.modifiedMs, isUtc: true)), null),
              2 => (m.strategyKey, null),
              3 => (
                  '${m.from ?? (span == null ? 'start' : fmtDate(span.$1))} → ${m.to ?? (span == null ? 'end' : fmtDate(span.$2))}',
                  vis ? null : C.gold,
                ),
              4 => (keyInputs(m), C.mute),
              5 => (vis && m.trades != null ? fmtInt(m.trades!) : '—', null),
              6 => vis ? (fmtMoneySigned(m.netProfit), (m.netProfit ?? 0) > 0 ? C.green : ((m.netProfit ?? 0) < 0 ? C.red : null)) : ('Protected', C.gold),
              7 => (m.ok ? 'ok' : m.result, m.ok ? C.mute : C.red),
              _ => (m.runId, C.mute),
            };
          },
        ),
      ),
    ]);
  }
}

