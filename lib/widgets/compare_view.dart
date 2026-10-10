import 'package:flutter/material.dart';

import '../run/run_data.dart';
import '../state/lab_state.dart';
import '../theme.dart';
import '../util/format.dart';
import 'common.dart';
import 'graph_view.dart';
import 'history_view.dart' show keyInputs;
import 'report.dart';

/// Two runs side by side: equity curves on one time axis, then every report field for A and B.
/// No difference column: it would be a number the engine didn't write.
class CompareView extends StatelessWidget {
  const CompareView({super.key, required this.lab, required this.data});
  final LabState lab;
  final CompareData data;

  @override
  Widget build(BuildContext context) {
    final a = data.a, b = data.b;
    final ra = [...settingRows(a), ...reportRows(a)], rb = [...settingRows(b), ...reportRows(b)];
    // Rows by (section, label); inputs differ between strategies, so the union is listed.
    final keys = <(String, String)>[];
    final va = <(String, String), ReportRow>{}, vb = <(String, String), ReportRow>{};
    for (final (rows, map) in [(ra, va), (rb, vb)]) {
      for (final r in rows) {
        final k = (r.section, r.label);
        if (!keys.contains(k)) keys.add(k);
        map[k] = r;
      }
    }
    Widget head(String tag, Color col, RunManifest m) => Expanded(
          child: Row(children: [
            Container(width: 14, height: 3, color: col),
            const SizedBox(width: 8),
            Flexible(
              child: Text('$tag  ${m.strategyKey} · ${m.from ?? 'start'} → ${m.to ?? 'end'} · ${keyInputs(m)}',
                  overflow: TextOverflow.ellipsis, style: ts(12, w: FontWeight.w500)),
            ),
          ]),
        );
    return Panel(
      shadow: const [BoxShadow(color: Color(0x8C000000), blurRadius: 60, offset: Offset(0, 16))],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 10, 8),
          child: Row(children: [
            Text('Compare runs', style: ts(15, w: FontWeight.w500)),
            const SizedBox(width: 20),
            head('A', C.text, a),
            const SizedBox(width: 16),
            head('B', C.blue, b),
            RoundIconButton(icon: AppIcons.close, color: C.mute, tooltip: 'Close', onTap: lab.closeCompare),
          ]),
        ),
        SizedBox(
          height: 260,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: data.loading
                ? Center(child: Text('Reading both equity files…', style: ts(12, color: C.mute)))
                : data.error != null
                    ? Center(child: Text(data.error!, style: ts(12, color: C.red)))
                    : EquityGraph(showBalance: false, series: [
                        GraphSeries(store: data.ea!, label: 'A', equityColor: C.text, balanceColor: C.text),
                        GraphSeries(store: data.eb!, label: 'B', equityColor: C.blue, balanceColor: C.blue),
                      ]),
          ),
        ),
        Container(
          height: 30,
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: const BoxDecoration(border: Border.symmetric(horizontal: BorderSide(color: C.line))),
          child: Row(children: [
            Expanded(flex: 3, child: Text('FIELD', style: capsLabel())),
            Expanded(flex: 4, child: Text('A', textAlign: TextAlign.right, style: capsLabel())),
            Expanded(flex: 4, child: Text('B', textAlign: TextAlign.right, style: capsLabel(color: C.blue))),
          ]),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: keys.length,
            itemExtent: 28,
            itemBuilder: (_, i) {
              final k = keys[i], x = va[k], y = vb[k];
              final newSection = i == 0 || keys[i - 1].$1 != k.$1;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: newSection ? C.line : C.rowLine))),
                child: Row(children: [
                  Expanded(
                    flex: 3,
                    child: Text.rich(TextSpan(children: [
                      if (newSection) TextSpan(text: '${k.$1.toUpperCase()}  ', style: capsLabel(color: C.gold)),
                      TextSpan(text: k.$2, style: ts(12, color: C.mute)),
                    ]), overflow: TextOverflow.ellipsis),
                  ),
                  Expanded(flex: 4, child: Text(x?.value ?? '—', textAlign: TextAlign.right, overflow: TextOverflow.ellipsis, style: ts(12, color: x?.color ?? C.text))),
                  Expanded(flex: 4, child: Text(y?.value ?? '—', textAlign: TextAlign.right, overflow: TextOverflow.ellipsis, style: ts(12, color: y?.color ?? C.text))),
                ]),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
          child: Text('A: ${a.runId} · ${fmtFull(DateTime.fromMillisecondsSinceEpoch(a.modifiedMs, isUtc: true))} UTC      '
              'B: ${b.runId} · ${fmtFull(DateTime.fromMillisecondsSinceEpoch(b.modifiedMs, isUtc: true))} UTC', style: ts(11, color: C.mute)),
        ),
      ]),
    );
  }
}
