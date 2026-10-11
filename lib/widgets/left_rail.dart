import 'package:flutter/material.dart';

import '../chart/chart_layer.dart';
import '../state/app_state.dart';
import '../state/lab_state.dart';
import '../theme.dart';
import '../util/format.dart';
import 'common.dart';
import 'fields.dart';
import 'indicators_panel.dart' show editIndicator;
import 'top_bar.dart' show engineColor, engineLabel;

class LogoMark extends StatelessWidget {
  const LogoMark({super.key});
  @override
  Widget build(BuildContext context) => Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(color: C.text, borderRadius: BorderRadius.circular(10)),
        alignment: Alignment.center,
        child: CustomPaint(size: const Size(18, 18), painter: _LogoPainter()),
      );
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final p = Paint()..color = C.bg;
    for (final r in const [Rect.fromLTWH(2, 9, 3, 6), Rect.fromLTWH(7.5, 3, 3, 12), Rect.fromLTWH(13, 2, 3, 5)]) {
      c.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(1)), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

String _fileName(String? p) => p == null ? '' : p.split(RegExp(r'[\\/]')).last;

class CollapsedRail extends StatelessWidget {
  const CollapsedRail({super.key, required this.lab});
  final LabState lab;

  @override
  Widget build(BuildContext context) {
    final s = lab.chart;
    return Panel(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(children: [
        const LogoMark(),
        const SizedBox(height: 16),
        for (final (icon, tip, onTap) in [
          (AppIcons.tester, 'Tester', () => s.toggleRight()),
          (AppIcons.indicators, 'Indicators', () => s.toggleIndicators()),
          (AppIcons.results, 'Results', () => s.toggleBottom()),
          (AppIcons.history, 'Run history', () => s.showTab(ResultsTab.history)),
          (AppIcons.tools, 'Layers and engine', () => s.toggleLeft(true)),
        ]) ...[
          RoundIconButton(icon: icon, size: 40, radius: 12, iconSize: 18, color: C.mute, tooltip: tip, onTap: onTap),
          const SizedBox(height: 6),
        ],
        const Spacer(),
        Tooltip(
          message: lab.engine.message ?? engineLabel(lab),
          child: Container(width: 8, height: 8, decoration: BoxDecoration(color: engineColor(lab.engine.status), shape: BoxShape.circle)),
        ),
        const SizedBox(height: 14),
        RoundIconButton(icon: AppIcons.expand, size: 40, radius: 12, iconSize: 18, color: C.mute, tooltip: 'Expand', onTap: () => s.toggleLeft(true)),
      ]),
    );
  }
}

class ExpandedRail extends StatelessWidget {
  const ExpandedRail({super.key, required this.lab});
  final LabState lab;

  @override
  Widget build(BuildContext context) {
    final s = lab.chart, m = s.run?.manifest, c = s.baseTf == null ? null : s.series[s.baseTf!];
    return Panel(
      shadow: const [BoxShadow(color: Color(0x8C000000), blurRadius: 60, offset: Offset(16, 0))],
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const LogoMark(),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Strategy Lab', style: ts(15, w: FontWeight.w600)),
                Text('Hummer engine backtests', style: ts(11, color: C.mute)),
              ]),
            ),
            RoundIconButton(icon: AppIcons.collapse, size: 30, color: C.mute, onTap: () => s.toggleLeft(false)),
          ]),
          const SizedBox(height: 22),
          const SectionLabel('Open run'),
          const SizedBox(height: 10),
          if (m != null && c != null)
            Panel(
              color: C.bg,
              radius: 12,
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(m.strategyKey, style: ts(14, w: FontWeight.w500)),
                _kv('Run', m.runId),
                _kv('Candles', _fileName(s.candlesPath)),
                _kv('Chart range', '${fmtDate(c.t[0])} → ${fmtDate(c.t[c.length - 1])}'),
                _kv('M1 bars', fmtInt(c.length)),
                _kv('Trades', fmtInt(s.run!.trades.length)),
                _kv('Drawing events', fmtInt(s.run!.data.drawings.length)),
              ]),
            )
          else
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(border: Border.all(color: C.line), borderRadius: BorderRadius.circular(12)),
              child: Text('No run open', style: ts(12, color: C.mute)),
            ),
          const SizedBox(height: 22),
          const SectionLabel('Layers'),
          const SizedBox(height: 6),
          for (final l in chartLayers)
            Opacity(
              opacity: l.available(s) ? 1 : 0.45,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(l.label, style: ts(13)),
                      const SizedBox(height: 2),
                      Text(l.description, style: ts(11, color: C.mute)),
                    ]),
                  ),
                  PillSwitch(value: l.available(s) && s.layersOn.contains(l.id), enabled: l.available(s), onChanged: (_) => s.toggleLayer(l.id)),
                ]),
              ),
            ),
          for (final i in lab.indicators.instances)
            Padding(
              key: ValueKey('rail-indicator-${i.uid}'),
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(i.label, overflow: TextOverflow.ellipsis, style: ts(13)),
                    const SizedBox(height: 2),
                    Text(i.status, maxLines: 2, overflow: TextOverflow.ellipsis, style: ts(11, color: i.state == 'failed' ? C.red : C.mute)),
                  ]),
                ),
                RoundIconButton(icon: AppIcons.study, size: 26, iconSize: 14, color: C.mute, tooltip: 'Edit inputs', onTap: () => editIndicator(lab, i)),
                RoundIconButton(icon: AppIcons.clear, size: 26, iconSize: 14, color: C.mute, tooltip: 'Remove', onTap: () => lab.indicators.remove(i)),
                const SizedBox(width: 4),
                PillSwitch(value: i.visible, onChanged: (v) => lab.indicators.setVisible(i, v)),
              ]),
            ),
          Row(children: [
            Expanded(
              child: Text(lab.indicators.instances.isEmpty ? 'No indicators attached' : '${lab.indicators.instances.length} indicator${lab.indicators.instances.length == 1 ? '' : 's'}',
                  style: ts(11, color: C.mute)),
            ),
            PillButton(label: 'Indicators…', icon: AppIcons.indicators, height: 26, fontSize: 11, onTap: () => s.toggleIndicators(true)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: Text(s.events.isEmpty ? 'No FVG events loaded' : '${fmtInt(s.events.length)} events · ${_fileName(s.eventsPath)}', overflow: TextOverflow.ellipsis, style: ts(11, color: C.mute))),
            if (s.events.isNotEmpty) PillButton(label: 'Clear', height: 26, fontSize: 11, onTap: s.clearEvents),
            const SizedBox(width: 6),
            PillButton(label: 'Load events', icon: AppIcons.upload, height: 26, fontSize: 11, enabled: s.busy == null, onTap: s.pickEvents),
          ]),
          const SizedBox(height: 22),
          const SectionLabel('Engine'),
          const SizedBox(height: 8),
          Row(children: [
            Container(width: 7, height: 7, decoration: BoxDecoration(color: engineColor(lab.engine.status), shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Expanded(child: Text(lab.engine.message ?? engineLabel(lab), style: ts(11.5, color: C.mute, height: 1.35))),
          ]),
          const SizedBox(height: 8),
          FormRow(label: 'Repository', labelWidth: 78, child: _PathField(value: lab.settings.engineRepo, hint: '/path/to/hummer-engine', onSubmit: (v) => lab.setEnginePaths(repo: v))),
          FormRow(
            label: 'Binary',
            labelWidth: 78,
            sub: 'Empty: <repository>/build/release/hummer. Press Enter to apply.',
            child: _PathField(value: lab.settings.engineBinary, hint: 'build/release/hummer', onSubmit: (v) => lab.setEnginePaths(binary: v)),
          ),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: PillButton(label: 'Restart engine', icon: AppIcons.restart, height: 30, fontSize: 12, enabled: !lab.engineBuilding, onTap: lab.restartEngine)),
            const SizedBox(width: 6),
            Expanded(
              child: PillButton(
                label: lab.engineBuilding ? 'Building…' : 'Build engine',
                icon: AppIcons.build,
                height: 30,
                fontSize: 12,
                color: (lab.freshness?.needsBuild ?? false) ? C.gold : null,
                borderColor: (lab.freshness?.needsBuild ?? false) ? C.gold : null,
                enabled: !lab.engineBuilding,
                onTap: lab.buildEngine,
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(children: [
          Text(k, style: ts(12, color: C.mute)),
          const SizedBox(width: 12),
          Expanded(child: Text(v, textAlign: TextAlign.right, overflow: TextOverflow.ellipsis, style: ts(12))),
        ]),
      );
}

/// Applied on Enter, so a half-typed path never restarts the engine.
class _PathField extends StatefulWidget {
  const _PathField({required this.value, required this.hint, required this.onSubmit});
  final String value, hint;
  final ValueChanged<String> onSubmit;
  @override
  State<_PathField> createState() => _PathFieldState();
}

class _PathFieldState extends State<_PathField> {
  late final _c = TextEditingController(text: widget.value);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(color: C.bg, border: Border.all(color: C.line), borderRadius: BorderRadius.circular(999)),
        child: TextField(
          controller: _c,
          onSubmitted: widget.onSubmit,
          style: ts(11.5),
          decoration: InputDecoration.collapsed(hintText: widget.hint, hintStyle: ts(11.5, color: C.mute)),
        ),
      );
}
