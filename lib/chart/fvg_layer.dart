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

  /// A zone's outcome is knowable only once the cursor has reached its resolution bar
  /// (and, while the hold-out is locked, never for hold-out events outside replay).
  static bool outcomeKnown(Zone z, LayerContext ctx) => ctx.cursor >= z.end && !ctx.state.outcomeHidden(z.ev);

  /// Grey until [outcomeKnown], then the outcome colour.
  static Color zoneColor(Zone z, LayerContext ctx) => outcomeKnown(z, ctx) ? outcomeColor(z.ev.outcome) : C.mute;

  /// Non-selected zones are drawn at this strength; the selected one at full.
  static const dimmed = 0.35;

  static bool isSelected(Zone z, LayerContext ctx) => ctx.state.selected == z.ev.id || ctx.state.pending == z.ev.id;

  /// "Selected only" hides every other zone (all zones show while nothing is selected).
  static bool drawn(Zone z, LayerContext ctx) {
    final s = ctx.state;
    if (!s.layersOn.contains('selected')) return true;
    final id = s.pending ?? s.selected;
    return id == null || s.zoneFor(id) == null || z.ev.id == id;
  }

  /// "Bounce · wick 0.44", "Break · wick 3.25"; while unresolved "Open · wick 0.31" (from bars ≤ cursor) or "Waiting".
  static String zoneLabel(Zone z, LayerContext ctx) {
    final ev = z.ev;
    if (outcomeKnown(z, ctx)) return '${outcomeLabel(ev.outcome)} · wick ${ev.maxWick.toStringAsFixed(2)}';
    if (ctx.state.outcomeHidden(ev)) return 'Hold-out';
    if (ctx.cursor < z.touch) return 'Waiting';
    return 'Open · wick ${runningDepth(ctx.candles, z, min(ctx.cursor, z.end)).toStringAsFixed(2)}';
  }

  /// The drawn zone under the mouse (the most recent one if several overlap).
  static Zone? hovered(ChartGeometry g, LayerContext ctx) {
    final hv = ctx.state.hover.value;
    if (hv == null) return null;
    final price = g.price(hv.y);
    Zone? hit;
    for (final (z, _, _, end) in _visibleZones(g, ctx)) {
      if (hv.bar >= z.start && hv.bar <= end && price >= z.ev.bottom && price <= z.ev.top) hit = z;
    }
    return hit;
  }

  static Iterable<(Zone, double, double, int)> _visibleZones(ChartGeometry g, LayerContext ctx) sync* {
    final cur = ctx.cursor;
    for (final z in ctx.state.zones) {
      if (z.formed > cur) continue; // knowable only once the third candle has closed
      if (!drawn(z, ctx)) continue;
      final end = cur >= z.end ? z.end : cur; // extends right while unresolved
      final x0 = g.x(z.start) - g.xs / 2, x1 = g.x(end) + g.xs / 2;
      if (x1 < 0 || x0 > g.plotW || z.ev.gap <= 0) continue;
      yield (z, x0, x1, end);
    }
  }

  @override
  void paintBelow(Canvas canvas, ChartGeometry g, LayerContext ctx) {
    final s = ctx.state, levels = s.layersOn.contains('levels');
    for (final (z, x0, x1, _) in _visibleZones(g, ctx)) {
      final ev = z.ev, known = outcomeKnown(z, ctx), col = zoneColor(z, ctx);
      final sel = isSelected(z, ctx), a = sel ? 1.0 : dimmed;
      final r = Rect.fromLTRB(x0, g.y(ev.top), x1, g.y(ev.bottom));
      canvas.drawRect(r, Paint()..color = col.withOpacity((known ? 0.14 : 0.10) * a));
      canvas.drawRect(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = sel ? 1.25 : 1
          ..color = sel ? C.gold : col.withOpacity(0.45 * a),
      );
      if (levels) {
        final q = Paint()..color = col.withOpacity(0.4 * a);
        for (final p in [0.25, 0.5, 0.75]) {
          dashH(canvas, x0, x1, g.y(ev.priceAtDepth(p)), q, dash: 1, gap: 3);
        }
        final la = (known ? 0.45 : 0.75) * a;
        dashH(canvas, x0, x1, g.y(ev.target(s.k)), Paint()..color = C.green.withOpacity(la));
        dashH(canvas, x0, x1, g.y(ev.fail(s.failBuffer)), Paint()..color = C.red.withOpacity(la));
      }
      if (ctx.isReplay && known && z.end > s.pulseFrom && z.end <= s.pulseTo && ctx.pulse > 0) {
        canvas.drawRect(r, Paint()..color = col.withOpacity(0.55 * ctx.pulse * a));
      }
    }
  }

  @override
  void paintAbove(Canvas canvas, ChartGeometry g, LayerContext ctx) {
    final s = ctx.state, cur = ctx.cursor, allLabels = s.layersOn.contains('labels');
    final hover = hovered(g, ctx);
    for (final (z, _, x1, end) in _visibleZones(g, ctx)) {
      final ev = z.ev, known = outcomeKnown(z, ctx), col = zoneColor(z, ctx);
      final sel = isSelected(z, ctx), a = sel ? 1.0 : dimmed;
      final yT = g.y(ev.top), yB = g.y(ev.bottom);
      if (cur >= z.touch) {
        final d = runningDepth(ctx.candles, z, min(cur, end));
        final yd = g.y(ev.priceAtDepth(d)), xf = g.x(z.touch);
        canvas.drawLine(Offset(xf - g.xs / 2, yd), Offset(x1, yd), Paint()..color = C.text.withOpacity(0.6 * a));
        final c = Offset(xf, g.y(ev.edge));
        canvas.drawCircle(c, 3, Paint()..color = C.bg.withOpacity(a));
        canvas.drawCircle(
          c,
          3,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.25
            ..color = C.text.withOpacity(a),
        );
      }
      // Labels: the selected zone and the hovered one; the Labels toggle shows all.
      final hot = identical(z, hover);
      if (allLabels || sel || hot) {
        final la = sel || hot ? 1.0 : dimmed;
        final color = sel ? C.gold : (known ? col : C.mute);
        drawText(canvas, zoneLabel(z, ctx), Offset(x1 + 6, (yT + yB) / 2), ts(10, color: color.withOpacity(la), w: FontWeight.w500, ls: 0.3));
      }
    }
  }
}
