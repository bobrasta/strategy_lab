import 'package:flutter/material.dart';

import '../chart/drawings_layer.dart';
import '../indicators/indicators_state.dart';
import '../state/lab_state.dart';
import '../theme.dart';
import 'common.dart';
import 'input_form.dart';
import 'tester_panel.dart' show baseNameOf, statusColor, statusLabel;

/// MT5's Navigator → Indicators, as the right drawer: the indicators in `indicators/*.cpp` with
/// Build and Add to chart, the inputs form, and the indicators attached to the chart.
class IndicatorsPanel extends StatelessWidget {
  const IndicatorsPanel({super.key, required this.lab});
  final LabState lab;

  @override
  Widget build(BuildContext context) {
    final ind = lab.indicators, s = lab.chart;
    return Panel(
      key: const ValueKey('indicators-panel'),
      shadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 48, offset: Offset(-16, 0))],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 10, 6),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Indicators', style: ts(15, w: FontWeight.w500)),
                const SizedBox(height: 2),
                Text('Navigator · indicators/*.cpp, computed by the engine', overflow: TextOverflow.ellipsis, style: ts(11, color: C.mute)),
              ]),
            ),
            RoundIconButton(icon: AppIcons.close, color: C.mute, tooltip: 'Close', onTap: () => s.toggleIndicators(false)),
          ]),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
            child: ind.unsupported != null
                ? _Unsupported(lab: lab)
                : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    _ChartSection(lab: lab),
                    const SizedBox(height: 18),
                    _ListSection(lab: lab),
                    if (ind.draft != null) ...[const SizedBox(height: 14), _Editor(lab: lab)],
                    const SizedBox(height: 18),
                    _AttachedSection(lab: lab),
                  ]),
          ),
        ),
      ]),
    );
  }
}

Widget _note(String text, {Color color = C.mute}) => Text(text, style: ts(12, color: color, height: 1.4));

class _Unsupported extends StatelessWidget {
  const _Unsupported({required this.lab});
  final LabState lab;

  @override
  Widget build(BuildContext context) => Container(
        key: const ValueKey('indicators-unsupported'),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: C.gold.withOpacity(0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: C.gold.withOpacity(0.45))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Icon(AppIcons.warn, size: 16, color: C.gold),
            const SizedBox(width: 8),
            Expanded(child: Text(lab.indicators.unsupported!, style: ts(12.5, color: C.gold, height: 1.4))),
          ]),
          const SizedBox(height: 8),
          _note('Indicators need an engine with the M7 indicator methods (list_indicators, start_indicator, …). Everything else keeps working.'),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: PillButton(
                label: lab.engineBuilding ? 'Building…' : 'Build engine',
                icon: AppIcons.build,
                height: 30,
                fontSize: 12,
                color: C.gold,
                borderColor: C.gold,
                enabled: !lab.engineBuilding,
                onTap: lab.buildEngine,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(child: PillButton(label: 'Restart engine', icon: AppIcons.restart, height: 30, fontSize: 12, enabled: !lab.engineBuilding, onTap: lab.restartEngine)),
          ]),
        ]),
      );
}

/// Which data the indicators are computed on: the chart's data file.
class _ChartSection extends StatelessWidget {
  const _ChartSection({required this.lab});
  final LabState lab;

  @override
  Widget build(BuildContext context) {
    final s = lab.chart, path = s.candlesPath, run = s.run?.manifest;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionLabel('Chart'),
      const SizedBox(height: 8),
      if (path != null) ...[
        Text(baseNameOf(path), overflow: TextOverflow.ellipsis, style: ts(12.5)),
        const SizedBox(height: 2),
        _note(run != null
            ? 'Data of the open run ${run.runId}. Indicators cover the whole file; the chart and the indicators stop at the run\'s end.'
            : 'The data file on its own. Indicators cover the whole file.'),
      ] else ...[
        _note('No chart is open. Indicators are computed on the data file the chart shows: open a run from History, or chart the Tester\'s data file.'),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: Text(baseNameOf(lab.settings.dataFile), overflow: TextOverflow.ellipsis, style: ts(12))),
          const SizedBox(width: 8),
          PillButton(
            key: const ValueKey('indicators-open-chart'),
            label: lab.opening != null ? 'Opening…' : 'Open chart',
            icon: AppIcons.data,
            height: 28,
            fontSize: 12,
            enabled: lab.opening == null,
            onTap: () => lab.openDataChart(),
          ),
        ]),
      ],
    ]);
  }
}

class _ListSection extends StatelessWidget {
  const _ListSection({required this.lab});
  final LabState lab;

  @override
  Widget build(BuildContext context) {
    final ind = lab.indicators, b = lab.build;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionLabel('Indicators'),
      const SizedBox(height: 6),
      if (!lab.engine.ready)
        _note('The indicator list comes from the engine, which is not ready.')
      else if (ind.listError != null)
        _note("The indicator list couldn't be read: ${ind.listError}", color: C.red)
      else if (!ind.listed)
        _note('Reading the indicator list…')
      else if (ind.list.isEmpty)
        _note('No indicators in indicators/*.cpp.')
      else
        for (final x in ind.list) _ListRow(lab: lab, info: x, building: b != null && b.running && b.kind == 'indicator' && b.name == x.name),
    ]);
  }
}

class _ListRow extends StatelessWidget {
  const _ListRow({required this.lab, required this.info, required this.building});
  final LabState lab;
  final StrategyInfo info;
  final bool building;

  @override
  Widget build(BuildContext context) {
    final needsBuild = info.status == 'stale' || info.status == 'not_built';
    final anyBuild = lab.build?.running ?? false;
    final editing = lab.indicators.draft?.name == info.name && lab.indicators.draft?.instance == null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Container(width: 7, height: 7, decoration: BoxDecoration(color: statusColor(info.status), shape: BoxShape.circle)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(info.name, overflow: TextOverflow.ellipsis, style: ts(13)),
            const SizedBox(height: 1),
            Text(building ? 'building…' : statusLabel(info.status), style: ts(11, color: building ? C.text : statusColor(info.status))),
          ]),
        ),
        PillButton(
          key: ValueKey('indicator-build-${info.name}'),
          label: building ? 'Building…' : (info.status == 'built' ? 'Rebuild' : 'Build'),
          icon: AppIcons.build,
          height: 28,
          fontSize: 12,
          color: needsBuild ? C.gold : null,
          borderColor: needsBuild ? C.gold : null,
          enabled: lab.engine.ready && !anyBuild,
          onTap: () => lab.buildIndicator(info.name),
        ),
        const SizedBox(width: 6),
        PillButton(
          key: ValueKey('indicator-add-${info.name}'),
          label: 'Add',
          icon: AppIcons.plus,
          height: 28,
          fontSize: 12,
          color: editing ? C.gold : null,
          borderColor: editing ? C.gold : null,
          enabled: lab.engine.ready && info.runnable,
          onTap: () => lab.indicators.openEditor(info.name),
        ),
      ]),
    );
  }
}

/// The inputs form (the Tester's), for adding an indicator or editing an attached one.
class _Editor extends StatelessWidget {
  const _Editor({required this.lab});
  final LabState lab;

  @override
  Widget build(BuildContext context) {
    final ind = lab.indicators, d = ind.draft!, sc = ind.schemaOf(d.name), err = ind.schemaErrors[d.name];
    final problems = ind.draftProblems();
    final editing = d.instance != null;
    return Container(
      key: const ValueKey('indicator-editor'),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(color: C.bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.lineHover)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text(editing ? 'Inputs · ${d.instance!.label}' : 'Add ${d.name} to the chart', overflow: TextOverflow.ellipsis, style: ts(13, w: FontWeight.w500)),
          ),
          if (d.values.isNotEmpty) HoverBox(onTap: ind.resetDraft, builder: (_, h) => Text('Reset to defaults', style: ts(11, color: h ? C.text : C.mute))),
        ]),
        const SizedBox(height: 6),
        if (err != null)
          _note(err, color: C.red)
        else if (sc == null)
          _note('Reading inputs…')
        else ...[
          if (sc.inputs.isEmpty) _note('This indicator has no inputs.'),
          for (final i in sc.inputs) InputRow(spec: i, value: d.value(i), labelWidth: 110, onChanged: (v) => ind.setDraft(i, v)),
          if (sc.plots.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('PLOTS', style: capsLabel()),
            const SizedBox(height: 4),
            for (final p in sc.plots)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  SizedBox(width: 22, child: CustomPaint(size: const Size(22, 8), painter: _Swatch(DrawingsLayer.colorOf(p.color), p.width, p.dashed))),
                  const SizedBox(width: 8),
                  Expanded(child: Text(p.label.isEmpty ? p.name : p.label, overflow: TextOverflow.ellipsis, style: ts(12))),
                  Text('${p.color} · ${p.style} · ${_w(p.width)}', style: ts(11, color: C.mute)),
                ]),
              ),
          ],
        ],
        if (problems.isNotEmpty && sc != null) ...[const SizedBox(height: 6), _note(problems.first, color: C.gold)],
        const SizedBox(height: 10),
        Row(children: [
          const Spacer(),
          PillButton(label: 'Cancel', height: 30, fontSize: 12, onTap: ind.closeEditor),
          const SizedBox(width: 6),
          PillButton(
            key: const ValueKey('indicator-apply'),
            label: editing ? 'Apply' : 'Add to chart',
            variant: PillVariant.primary,
            height: 30,
            fontSize: 12,
            enabled: problems.isEmpty,
            onTap: ind.applyDraft,
          ),
        ]),
      ]),
    );
  }

  static String _w(double w) => w == w.truncateToDouble() ? '${w.toInt()} px' : '$w px';
}

class _Swatch extends CustomPainter {
  _Swatch(this.color, this.width, this.dashed);
  final Color color;
  final double width;
  final bool dashed;

  @override
  void paint(Canvas c, Size s) {
    final p = Paint()
      ..color = color
      ..strokeWidth = width.clamp(0.5, 4.0).toDouble();
    final y = s.height / 2;
    if (!dashed) {
      c.drawLine(Offset(0, y), Offset(s.width, y), p);
      return;
    }
    for (var x = 0.0; x < s.width; x += 7) {
      c.drawLine(Offset(x, y), Offset((x + 4).clamp(0, s.width).toDouble(), y), p);
    }
  }

  @override
  bool shouldRepaint(covariant _Swatch old) => old.color != color || old.width != width || old.dashed != dashed;
}

class _AttachedSection extends StatelessWidget {
  const _AttachedSection({required this.lab});
  final LabState lab;

  @override
  Widget build(BuildContext context) {
    final ind = lab.indicators;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionLabel('On the chart'),
      const SizedBox(height: 8),
      if (ind.instances.isEmpty)
        _note('None yet. Add one above; it is computed by the engine and drawn on the chart. Several can be attached, also of the same indicator.')
      else
        for (final i in ind.instances) ...[InstanceCard(lab: lab, instance: i), const SizedBox(height: 8)],
    ]);
  }
}

/// One attached indicator: label, visibility, status (progress, counts or the failure with the
/// journal / stderr tails), Edit inputs and Remove.
class InstanceCard extends StatelessWidget {
  const InstanceCard({super.key, required this.lab, required this.instance});
  final LabState lab;
  final IndicatorInstance instance;

  @override
  Widget build(BuildContext context) {
    final i = instance, ind = lab.indicators, failed = i.state == 'failed';
    final editing = ind.draft?.instance == i;
    return Container(
      key: ValueKey('indicator-instance-${i.uid}'),
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(color: C.bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: editing ? C.gold.withOpacity(0.5) : C.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(i.label, overflow: TextOverflow.ellipsis, style: ts(13, w: FontWeight.w500))),
          Tooltip(message: i.visible ? 'Hide' : 'Show', child: PillSwitch(value: i.visible, onChanged: (v) => ind.setVisible(i, v))),
        ]),
        const SizedBox(height: 4),
        Text(i.status, maxLines: 3, overflow: TextOverflow.ellipsis, style: ts(11.5, color: failed ? C.red : C.mute, height: 1.35)),
        if (i.active && i.state != 'loading') ...[
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(value: i.pct <= 0 ? null : i.pct / 100, minHeight: 3, backgroundColor: C.line, color: C.gold),
          ),
        ],
        if (failed && (i.journalTail.isNotEmpty || i.stderrTail.isNotEmpty)) ...[
          const SizedBox(height: 6),
          Container(
            constraints: const BoxConstraints(maxHeight: 110),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: C.panel, borderRadius: BorderRadius.circular(8), border: Border.all(color: C.line)),
            child: SingleChildScrollView(child: SelectableText([...i.stderrTail, ...i.journalTail].join('\n'), style: ts(10.5, color: C.mute, height: 1.3))),
          ),
        ],
        if (i.output != null && i.output!.warnings.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(i.output!.warnings.join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis, style: ts(11, color: C.gold, height: 1.35)),
        ],
        const SizedBox(height: 8),
        Row(children: [
          if (failed || i.state == 'stopped') ...[
            PillButton(label: 'Retry', icon: AppIcons.restart, height: 26, fontSize: 11, enabled: lab.engine.ready && lab.chart.candlesPath != null, onTap: () => ind.recompute(i)),
            const SizedBox(width: 6),
          ],
          const Spacer(),
          PillButton(
            key: ValueKey('indicator-edit-${i.uid}'),
            label: 'Edit inputs',
            height: 26,
            fontSize: 11,
            color: editing ? C.gold : null,
            borderColor: editing ? C.gold : null,
            onTap: () => editIndicator(lab, i),
          ),
          const SizedBox(width: 6),
          PillButton(key: ValueKey('indicator-remove-${i.uid}'), label: 'Remove', icon: AppIcons.clear, height: 26, fontSize: 11, onTap: () => ind.remove(i)),
        ]),
      ]),
    );
  }
}

/// Opens the Indicators drawer with [i]'s inputs form (from the panel or the Layers rail).
void editIndicator(LabState lab, IndicatorInstance i) {
  lab.chart.toggleIndicators(true);
  lab.indicators.openEditor(i.name, instance: i);
}
