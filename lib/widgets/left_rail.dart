import 'package:flutter/material.dart';

import '../chart/chart_layer.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../util/format.dart';
import 'common.dart';

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
  const CollapsedRail({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) => Panel(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(children: [
          const LogoMark(),
          const SizedBox(height: 16),
          for (final (icon, tip) in const [(AppIcons.data, 'Data'), (AppIcons.tools, 'Tools'), (AppIcons.study, 'FVG study')]) ...[
            RoundIconButton(icon: icon, size: 40, radius: 12, iconSize: 18, color: C.mute, tooltip: tip, onTap: () => state.toggleLeft(true)),
            const SizedBox(height: 6),
          ],
          const Spacer(),
          RoundIconButton(icon: AppIcons.expand, size: 40, radius: 12, iconSize: 18, color: C.mute, tooltip: 'Expand', onTap: () => state.toggleLeft(true)),
        ]),
      );
}

class ExpandedRail extends StatelessWidget {
  const ExpandedRail({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final s = state, c = s.baseTf == null ? null : s.series[s.baseTf!];
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
                Text('FVG Lab', style: ts(15, w: FontWeight.w600)),
                Text('Gap reaction research', style: ts(11, color: C.mute)),
              ]),
            ),
            RoundIconButton(icon: AppIcons.collapse, size: 30, color: C.mute, onTap: () => s.toggleLeft(false)),
          ]),
          const SizedBox(height: 22),
          Row(children: [
            const SectionLabel('Data'),
            const Spacer(),
            if (s.isSample) Text('SAMPLE DATA', style: capsLabel(color: C.gold)),
          ]),
          const SizedBox(height: 10),
          if (c != null || s.eventsLoaded)
            Panel(
              color: C.bg,
              radius: 12,
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (c != null) ...[
                  Row(children: [
                    Text('XAUUSD', style: ts(14, w: FontWeight.w500)),
                    const SizedBox(width: 8),
                    _tag(c.tf),
                  ]),
                  if (s.candlesPath != null) _kv('Candles', _fileName(s.candlesPath)),
                  _kv('Range', '${fmtFull(c.time(0)).substring(0, 10)} → ${fmtFull(c.time(c.length - 1)).substring(0, 10)}'),
                  _kv('Bars', fmtInt(c.length)),
                ] else
                  Text('No candles loaded', style: ts(12, color: C.mute)),
                const SizedBox(height: 6),
                if (s.eventsLoaded) ...[
                  if (s.eventsPath != null) _kv('Events', _fileName(s.eventsPath)),
                  _kv('First touches', fmtInt(s.events.length)),
                  _kv('Events timeframe', s.eventsTf ?? '—'),
                  if (s.unmatchedEvents > 0) _kv('Not on chart', fmtInt(s.unmatchedEvents)),
                  _kv('Fake / control', '${s.fakeEvents.isEmpty ? '—' : fmtInt(s.fakeEvents.length)} / ${s.controlEvents.isEmpty ? '—' : fmtInt(s.controlEvents.length)}'),
                  _kv('Hold-out 2026', s.holdoutLocked ? 'Locked' : 'Revealed ${fmtFull(s.holdoutRevealedAt!).substring(0, 10)}'),
                  _kv('Starred', fmtInt(s.bookmarks.starredCount)),
                ] else
                  _kv('Events', 'Not loaded'),
              ]),
            )
          else
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(border: Border.all(color: C.line), borderRadius: BorderRadius.circular(12)),
              child: Text('No dataset loaded', style: ts(12, color: C.mute)),
            ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: PillButton(label: 'Load candles', icon: AppIcons.upload, fontSize: 12, enabled: s.busy == null, onTap: s.pickCandles)))),
            const SizedBox(width: 6),
            Expanded(child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: PillButton(label: 'Load events', icon: AppIcons.upload, fontSize: 12, enabled: s.busy == null, onTap: s.pickEvents)))),
          ]),
          const SizedBox(height: 22),
          const SectionLabel('Tools'),
          const SizedBox(height: 6),
          for (final l in chartLayers)
            Opacity(
              opacity: l.available ? 1 : 0.45,
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
                  PillSwitch(value: l.available && s.layersOn.contains(l.id), enabled: l.available, onChanged: (_) => s.toggleLayer(l.id)),
                ]),
              ),
            ),
          const SizedBox(height: 18),
          const SectionLabel('FVG study display'),
          const SizedBox(height: 6),
          _StepperRow(
            label: 'Bounce target K',
            unit: '× gap beyond entry edge',
            value: s.k.toStringAsFixed(2),
            onDec: () => s.setK(s.k - 0.25),
            onInc: () => s.setK(s.k + 0.25),
          ),
          _StepperRow(
            label: 'Fail buffer',
            unit: '× gap beyond far edge',
            value: s.failBuffer.toStringAsFixed(2),
            onDec: () => s.setFailBuffer(s.failBuffer - 0.05),
            onInc: () => s.setFailBuffer(s.failBuffer + 0.05),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Display only. These move the target and fail lines on the chart. Outcomes and stats come from the Python study, so re-run it and reload to change them.',
              style: ts(11, color: C.mute, height: 1.4),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _tag(String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        decoration: BoxDecoration(border: Border.all(color: C.line), borderRadius: BorderRadius.circular(999)),
        child: Text(t, style: ts(11, color: C.mute)),
      );

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(children: [
          Text(k, style: ts(12, color: C.mute)),
          const SizedBox(width: 12),
          Expanded(child: Text(v, textAlign: TextAlign.right, overflow: TextOverflow.ellipsis, style: ts(12))),
        ]),
      );
}

class _StepperRow extends StatelessWidget {
  const _StepperRow({required this.label, required this.unit, required this.value, required this.onDec, required this.onInc});
  final String label, unit, value;
  final VoidCallback onDec, onInc;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: ts(13)),
              const SizedBox(height: 2),
              Text(unit, style: ts(11, color: C.mute)),
            ]),
          ),
          Container(
            height: 28,
            decoration: BoxDecoration(border: Border.all(color: C.line), borderRadius: BorderRadius.circular(999)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              RoundIconButton(icon: AppIcons.minus, size: 26, iconSize: 14, color: C.mute, onTap: onDec),
              SizedBox(width: 38, child: Text(value, textAlign: TextAlign.center, style: ts(12))),
              RoundIconButton(icon: AppIcons.plus, size: 26, iconSize: 14, color: C.mute, onTap: onInc),
            ]),
          ),
        ]),
      );
}
