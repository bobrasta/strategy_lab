import 'dart:math';

import 'package:flutter/painting.dart';

import '../data/events.dart';
import '../theme.dart';
import 'chart_geometry.dart';
import 'chart_layer.dart';
import 'paint_utils.dart';

/// Draws zones from fvg_events.csv. Geometry (edge/far) and outcome come from
/// Python; only the running max-depth line is measured here, from bars ≤ cursor.
class FvgLayer extends ChartLayer {
  const FvgLayer();
  @override
  String get id => 'fvg';
  @override
  String get label => 'Fair Value Gaps';
  @override
  String get description => 'Zones from fvg_events.csv';

  static Color outcomeColor(EvOutcome o) => switch (o) {
        EvOutcome.bounce => C.green,
        EvOutcome.through => C.red,
        EvOutcome.timeout => C.mute,
      };

  Iterable<(Zone, double, double, int)> _visible(ChartGeometry g, LayerContext ctx) sync* {
    final cur = ctx.cursor;
    for (final z in ctx.state.zones) {
      if (z.formed > cur) continue; // knowable only once the third candle has closed
      final end = cur >= z.end ? z.end : cur; // extends right while unresolved
      final x0 = g.x(z.start) - g.xs / 2, x1 = g.x(end) + g.xs / 2;
      if (x1 < 0 || x0 > g.plotW || z.ev.gap <= 0) continue;
      yield (z, x0, x1, end);
    }
  }

  @override
  void paintBelow(Canvas canvas, ChartGeometry g, LayerContext ctx) {
    final s = ctx.state, cur = ctx.cursor, levels = s.layersOn.contains('levels');
    for (final (z, x0, x1, _) in _visible(g, ctx)) {
      final ev = z.ev, known = cur >= z.end && !s.outcomeHidden(ev), col = known ? outcomeColor(ev.outcome) : C.mute;
      final sel = s.selected == ev.id || s.pending == ev.id;
      final r = Rect.fromLTRB(x0, g.y(ev.top), x1, g.y(ev.bottom));
      canvas.drawRect(r, Paint()..color = col.withOpacity(known ? 0.14 : 0.10));
      canvas.drawRect(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = sel ? 1.25 : 1
          ..color = sel ? C.gold : col.withOpacity(0.45),
      );
      if (levels) {
        final q = Paint()..color = col.withOpacity(0.4);
        for (final p in [0.25, 0.5, 0.75]) {
          dashH(canvas, x0, x1, g.y(ev.priceAtDepth(p)), q, dash: 1, gap: 3);
        }
        final a = known ? 0.45 : 0.75;
        dashH(canvas, x0, x1, g.y(ev.target(s.k)), Paint()..color = C.green.withOpacity(a));
        dashH(canvas, x0, x1, g.y(ev.fail(s.failBuffer)), Paint()..color = C.red.withOpacity(a));
      }
      if (ctx.isReplay && known && z.end > s.pulseFrom && z.end <= s.pulseTo && ctx.pulse > 0) {
        canvas.drawRect(r, Paint()..color = col.withOpacity(0.55 * ctx.pulse));
      }
    }
  }

  @override
  void paintAbove(Canvas canvas, ChartGeometry g, LayerContext ctx) {
    final s = ctx.state, cur = ctx.cursor, labels = s.layersOn.contains('labels');
    for (final (z, _, x1, end) in _visible(g, ctx)) {
      final ev = z.ev, known = cur >= z.end && !s.outcomeHidden(ev), col = known ? outcomeColor(ev.outcome) : C.mute;
      final sel = s.selected == ev.id || s.pending == ev.id;
      final yT = g.y(ev.top), yB = g.y(ev.bottom);
      final touched = cur >= z.touch;
      var lab = known
          ? outcomeLabel(ev.outcome).toUpperCase()
          : (s.outcomeHidden(ev) ? 'HOLD-OUT' : (touched ? 'OPEN' : 'WAITING'));
      if (touched) {
        final d = runningDepth(ctx.candles, z, min(cur, end));
        final yd = g.y(ev.priceAtDepth(d)), xf = g.x(z.touch);
        canvas.drawLine(Offset(xf - g.xs / 2, yd), Offset(x1, yd), Paint()..color = C.text.withOpacity(0.6));
        final c = Offset(xf, g.y(ev.edge));
        canvas.drawCircle(c, 3, Paint()..color = C.bg);
        canvas.drawCircle(
          c,
          3,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.25
            ..color = C.text,
        );
        lab += '  ${d.toStringAsFixed(2)}';
      }
      if (labels) {
        drawText(canvas, lab, Offset(x1 + 6, (yT + yB) / 2), ts(10, color: sel ? C.gold : (known ? col : C.mute), w: FontWeight.w500, ls: 0.6));
      }
    }
  }
}
