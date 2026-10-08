import 'dart:math';

import 'package:flutter/material.dart';

import '../chart/paint_utils.dart';
import '../data/baseline.dart';
import '../data/stats.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../util/format.dart';
import 'chart_overlays.dart' show confirmRevealHoldout;
import 'common.dart';

class StatsDrawer extends StatelessWidget {
  const StatsDrawer({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final s = state, st = s.stats;
    String pct(double? v) => v == null ? '—' : '${(v * 100).toStringAsFixed(1)}%';
    final bounce = splitDecimal(pct(st.bounceRate));
    final brk = splitDecimal(pct(st.breakRate));
    final depth = splitDecimal(st.medianWick?.toStringAsFixed(2) ?? '—');
    final bars = splitDecimal(st.avgBars?.toStringAsFixed(1) ?? '—');
    final mins = ((st.avgBars ?? 0) * tfMinutesOf(s.eventsTf)).round();
    final filteredNote = st.total == s.events.length ? 'all events in file' : 'of ${fmtInt(s.events.length)} in file';
    final fake = s.fakeCurve;
    final base = fake != null
        ? [for (var i = 0; i < fake.length; i++) if (fake[i] != null) (i / 10, fake[i]!)]
        : [for (final p in s.baseline?.curve ?? const <BaselinePoint>[]) if (p.fake != null) (p.d, p.fake!)];
    final baseLabel = fake != null ? 'Fake zones (same filters)' : (s.baseline != null ? 'Fake zones (all events, from JSON)' : 'No fake zones loaded');

    return Panel(
      shadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 48, offset: Offset(-16, 0))],
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Study summary', style: ts(15, w: FontWeight.w500)),
                const SizedBox(height: 4),
                Text(
                  s.isSample ? 'Sample data · not from your study' : 'From fvg_events.csv${s.eventsTf != null ? ' · ${s.eventsTf}' : ''} · timeouts excluded from rates',
                  style: ts(12, color: s.isSample ? C.gold : C.mute),
                ),
              ]),
            ),
            RoundIconButton(icon: AppIcons.close, color: C.mute, onTap: s.toggleRight),
          ]),
          const SizedBox(height: 16),
          if (s.statsLocked)
            _HoldoutLocked(state: s)
          else ...[
            if (s.holdoutExcluded > 0) ...[_holdoutNote(context, s), const SizedBox(height: 12)],
            _ComparisonCard(state: s),
            const SizedBox(height: 8),
            LayoutBuilder(builder: (context, c) {
              final w = (c.maxWidth - 8) / 2;
              return Wrap(spacing: 8, runSpacing: 8, children: [
                _Card(width: w, label: 'Total first touches', value: BigNumber(fmtInt(st.total), ''), sub: filteredNote),
                _Card(width: w, label: 'Bounce rate', dot: C.green, value: BigNumber(bounce.$1, bounce.$2), sub: '${fmtInt(st.bounces)} of ${fmtInt(st.resolved)} resolved'),
                _Card(width: w, label: 'Break-through rate', dot: C.red, value: BigNumber(brk.$1, brk.$2), sub: '${fmtInt(st.timeouts)} timeouts (${pct(st.timeoutShare)}) excluded'),
                _Card(width: w, label: 'Median depth reached', value: BigNumber(depth.$1, depth.$2), sub: 'max wick, gap units'),
                _Card(width: w, label: 'Avg bars to resolve', value: BigNumber(bars.$1, bars.$2), sub: st.avgBars == null ? 'no resolved events' : '≈ ${mins ~/ 60} h ${mins % 60} m'),
              ]);
            }),
            const SizedBox(height: 22),
            Text('P(bounce) once price reaches depth d', style: ts(13, w: FontWeight.w500)),
            const SizedBox(height: 4),
            Row(children: [
              _legend(C.green, 2, 'Real gaps'),
              const SizedBox(width: 14),
              Flexible(child: _legend(C.mute, 1, baseLabel)),
            ]),
            const SizedBox(height: 4),
            Text('Non-timeout events with max wick ≥ d · hidden where n < $kMinCurveN', style: ts(11, color: C.mute)),
            const SizedBox(height: 10),
            AspectRatio(aspectRatio: 348 / 156, child: CustomPaint(painter: _CurvePainter(st.curve, base))),
            const SizedBox(height: 22),
            Text('Where clean bounces turned', style: ts(13, w: FontWeight.w500)),
            const SizedBox(height: 4),
            Text('Max wick depth of bounce events, 0.1-gap buckets · n = ${fmtInt(st.bounces)}', style: ts(11, color: C.mute)),
            const SizedBox(height: 10),
            AspectRatio(aspectRatio: 348 / 124, child: CustomPaint(painter: _HistPainter(st.hist))),
          ],
        ]),
      ),
    );
  }

  Widget _holdoutNote(BuildContext context, AppState s) => Row(children: [
        const Icon(Icons.lock_outline, size: 14, color: C.mute),
        const SizedBox(width: 6),
        Expanded(child: Text('${fmtInt(s.holdoutExcluded)} hold-out 2026 events excluded (locked)', style: ts(11, color: C.mute))),
        PillButton(label: 'Reveal hold-out', height: 26, fontSize: 11, onTap: () => confirmRevealHoldout(context, s)),
      ]);

  Widget _legend(Color c, double h, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 14, height: h, color: c),
        const SizedBox(width: 6),
        Flexible(child: Text(t, overflow: TextOverflow.ellipsis, style: ts(11, color: C.mute))),
      ]);
}

class _HoldoutLocked extends StatelessWidget {
  const _HoldoutLocked({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) => Panel(
        color: C.bg,
        radius: 12,
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.lock_outline, size: 18, color: C.mute),
          const SizedBox(height: 10),
          Text('Hold-out 2026 is locked', style: ts(14, w: FontWeight.w500)),
          const SizedBox(height: 6),
          Text(
            'Stats for these events stay hidden until your rules are frozen. Replay can still play hold-out bars. '
            'Revealing records the date in fvg_holdout.json.',
            style: ts(12, color: C.mute, height: 1.45),
          ),
          const SizedBox(height: 14),
          PillButton(label: 'Reveal hold-out', icon: Icons.lock_open_outlined, onTap: () => confirmRevealHoldout(context, state)),
        ]),
      );
}

/// Real vs fake vs control for the active filter and period, with a verdict.
class _ComparisonCard extends StatelessWidget {
  const _ComparisonCard({required this.state});
  final AppState state;

  static (String, Color) verdictStyle(Verdict v, Comparison c) => switch (v) {
        Verdict.candidate => ('Candidate', C.green),
        Verdict.artifact => ('Artifact', C.red),
        Verdict.noEdge => ('No edge', C.mute),
        Verdict.needsData => (c.fake == null || c.control == null ? 'Needs fake + control files' : 'Too few events', C.mute),
      };

  @override
  Widget build(BuildContext context) {
    final s = state, c = s.comparison, v = c.verdict;
    final (vLabel, vColor) = verdictStyle(v, c);
    String rate(RateSummary? r) => r?.rate == null ? '—' : '${(r!.rate! * 100).toStringAsFixed(1)}%';
    String n(RateSummary? r) => r == null ? 'not loaded' : 'n ${fmtInt(r.resolved)}';
    String diff(double? pp, double? z) => pp == null ? '—' : '${fmtSigned(pp, digits: 1)} pp${z == null ? '' : ' · z ${z.toStringAsFixed(1)}'}';
    final period = kFilterOptions['Period']![s.filters['Period']!];

    Widget col(String label, RateSummary? r, Color color) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: ts(11, color: C.mute)),
            const SizedBox(height: 4),
            Builder(builder: (_) {
              final parts = splitDecimal(rate(r));
              return BigNumber(parts.$1, parts.$2, size: 22, color: color);
            }),
            const SizedBox(height: 2),
            Text(n(r), style: ts(11, color: C.mute)),
          ]),
        );

    Widget row(String k, String v2, {bool strong = false}) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(children: [
            Expanded(child: Text(k, style: ts(12, color: C.mute))),
            Text(v2, style: ts(12, w: strong ? FontWeight.w500 : FontWeight.w400)),
          ]),
        );

    return Panel(
      color: C.bg,
      radius: 12,
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text('Real vs fake vs control', style: ts(12, color: C.mute))),
          Container(
            height: 22,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: vColor.withOpacity(vColor == C.mute ? 0.12 : 0.13),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: vColor.withOpacity(0.5)),
            ),
            child: Text(vLabel, style: ts(11, color: vColor == C.mute ? C.text : vColor, w: FontWeight.w500)),
          ),
        ]),
        const SizedBox(height: 4),
        Text(s.anyFilter ? 'Active filter · $period period' : 'All events · $period period', style: ts(11, color: C.mute)),
        const SizedBox(height: 12),
        Row(children: [
          col('Real', c.real, C.text),
          col('Fake', c.fake, C.mute),
          col('Control', c.control, C.mute),
        ]),
        const SizedBox(height: 8),
        row('Real − fake', diff(c.realMinusFakePp, c.zRealFake), strong: true),
        row('Control − fake', diff(c.controlMinusFakePp, c.zControlFake)),
        row('Real − control', diff(c.realMinusControlPp, c.zRealControl)),
        const SizedBox(height: 8),
        Text(
          'Candidate: real beats fake and control (z ≥ 2 each). Artifact: real beats fake but matches control. '
          'Rates exclude timeouts; min $kMinVerdictN resolved per group.',
          style: ts(10.5, color: C.mute, height: 1.4),
        ),
      ]),
    );
  }
}

int tfMinutesOf(String? tf) => switch (tf) {
      'M1' => 1,
      'M5' => 5,
      'H1' => 60,
      _ => 15,
    };

class _Card extends StatelessWidget {
  const _Card({required this.width, required this.label, required this.value, required this.sub, this.dot});
  final double width;
  final String label, sub;
  final Widget value;
  final Color? dot;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: Panel(
          color: C.bg,
          radius: 12,
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (dot != null) ...[
                Container(width: 6, height: 6, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
                const SizedBox(width: 6),
              ],
              Flexible(child: Text(label, style: ts(12, color: C.mute), overflow: TextOverflow.ellipsis)),
            ]),
            const SizedBox(height: 6),
            SizedBox(height: 32, child: Align(alignment: Alignment.centerLeft, child: value)),
            const SizedBox(height: 6),
            Text(sub, style: ts(11, color: C.mute)),
          ]),
        ),
      );
}

class _CurvePainter extends CustomPainter {
  _CurvePainter(this.real, this.base);
  final List<double?> real;
  final List<(double, double)> base;

  @override
  void paint(Canvas c, Size size) {
    const l = 32.0, r = 8.0, t = 8.0, b = 22.0;
    double x(double d) => l + d / 1.3 * (size.width - l - r);
    double y(double p) => t + (1 - p) * (size.height - t - b);
    final st = ts(10, color: C.mute);
    final grid = Paint()..color = C.line;
    for (final p in [0.25, 0.5, 0.75]) {
      dashH(c, l, size.width - r, y(p), grid, dash: 1, gap: 3);
      drawText(c, '${(p * 100).round()}%', Offset(l - 6, y(p)), st, align: TextAlign.right);
    }
    for (final d in [0.0, 0.5, 1.0, 1.3]) {
      drawText(c, d.toStringAsFixed(1), Offset(x(d), size.height - 8), st, align: TextAlign.center);
    }
    dashV(c, x(1), t, size.height - b, Paint()..color = C.mute, dash: 3, gap: 3);
    drawText(c, 'far edge', Offset(x(1) + 4, t + 6), st);
    c.drawLine(Offset(l, size.height - b), Offset(size.width - r, size.height - b), grid);

    void line(List<(double, double)> pts, Paint p) {
      final path = Path();
      for (var i = 0; i < pts.length; i++) {
        final o = Offset(x(pts[i].$1), y(pts[i].$2));
        i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
      }
      c.drawPath(path, p);
    }

    line(base.where((p) => p.$1 <= 1.3).toList(),
        Paint()
          ..style = PaintingStyle.stroke
          ..color = C.mute.withOpacity(0.7));
    final realPts = [for (var i = 0; i < real.length; i++) if (real[i] != null) (i / 10, real[i]!)];
    line(realPts,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = C.green);
  }

  @override
  bool shouldRepaint(covariant _CurvePainter old) => old.real != real || old.base != base;
}

class _HistPainter extends CustomPainter {
  _HistPainter(this.hist);
  final List<int> hist;

  @override
  void paint(Canvas c, Size size) {
    if (hist.isEmpty) return;
    const b = 20.0, t = 16.0;
    final mx = max(1, hist.fold<int>(0, max));
    final bw = size.width / hist.length;
    final st = ts(10, color: C.mute);
    for (var i = 0; i < hist.length; i++) {
      final h = hist[i] / mx * (size.height - b - t);
      final top = hist[i] == mx;
      c.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(i * bw + 2, size.height - b - h, bw - 4, h), const Radius.circular(3)),
        Paint()..color = C.text.withOpacity(top ? 0.55 : 0.22),
      );
      if (top && hist[i] > 0) drawText(c, fmtInt(hist[i]), Offset(i * bw + bw / 2, size.height - b - h - 8), ts(10), align: TextAlign.center);
    }
    c.drawLine(Offset(0, size.height - b), Offset(size.width, size.height - b), Paint()..color = C.line);
    drawText(c, '0', Offset(0, size.height - 8), st);
    drawText(c, '0.5', Offset(5 * bw, size.height - 8), st, align: TextAlign.center);
    drawText(c, '1.0', Offset(10 * bw, size.height - 8), st, align: TextAlign.center);
    drawText(c, '${((hist.length - 1) / 10).toStringAsFixed(1)}+', Offset(size.width, size.height - 8), st, align: TextAlign.right);
  }

  @override
  bool shouldRepaint(covariant _HistPainter old) => old.hist != hist;
}
