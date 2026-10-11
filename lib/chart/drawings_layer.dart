import 'dart:math';

import 'package:flutter/painting.dart';

import '../run/run_view.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'chart_geometry.dart';
import 'chart_layer.dart';
import 'paint_utils.dart';

/// What the strategy drew (drawings.jsonl), in the state as of the cursor: only events stamped
/// at or before it are applied, and open-ended objects extend to the cursor.
class DrawingsLayer extends ChartLayer {
  const DrawingsLayer();
  @override
  String get id => 'drawings';
  @override
  String get label => 'Strategy drawings';
  @override
  String get description => 'Markers, lines and zones from drawings.jsonl';
  @override
  bool available(AppState s) => s.run != null;

  static Color colorOf(String token) => switch (token) {
        'green' => C.green,
        'red' => C.red,
        'accent' => C.gold,
        'amber' => C.amber,
        'blue' => C.blue,
        _ => C.mute,
      };

  @override
  void paintBelow(Canvas canvas, ChartGeometry g, LayerContext ctx) {
    final run = ctx.state.run;
    if (run != null) paintZones(canvas, g, ctx, run.drawingsAt(ctx.nowMs));
  }

  @override
  void paintAbove(Canvas canvas, ChartGeometry g, LayerContext ctx) {
    final run = ctx.state.run;
    if (run != null) paintObjects(canvas, g, ctx, run.drawingsAt(ctx.nowMs));
  }

  /// Zones as of the cursor (below the candles). Shared with indicator objects.
  static void paintZones(Canvas canvas, ChartGeometry g, LayerContext ctx, Iterable<DrawObj> objs) {
    final (from, to) = ctx.viewSpan(g);
    for (final o in objs) {
      if (o.kind != 'zone') continue;
      final end = o.t2 ?? ctx.nowMs;
      if (end < from || o.t1 > to) continue;
      final col = colorOf(o.color);
      final r = Rect.fromLTRB(g.x(ctx.bar(o.t1)) - g.xs / 2, g.y(max(o.p1, o.p2)), g.x(ctx.bar(min(end, ctx.nowMs))) + g.xs / 2, g.y(min(o.p1, o.p2)));
      canvas.drawRect(r, Paint()..color = col.withOpacity(0.10));
      canvas.drawRect(r, Paint()
        ..style = PaintingStyle.stroke
        ..color = col.withOpacity(0.40));
    }
  }

  /// Markers, lines and the hover label (above the candles). Shared with indicator objects.
  static void paintObjects(Canvas canvas, ChartGeometry g, LayerContext ctx, Iterable<DrawObj> objs) {
    final (from, to) = ctx.viewSpan(g);
    final hv = ctx.state.hover.value;
    final hp = hv == null ? null : Offset(g.x(hv.bar), hv.y);
    DrawObj? label;
    for (final o in objs) {
      final col = colorOf(o.color);
      switch (o.kind) {
        case 'marker':
          if (o.t1 < from || o.t1 > to) continue;
          final p = Offset(g.x(ctx.bar(o.t1)), g.y(o.p1));
          _marker(canvas, p, o.shape ?? 'dot', col);
          if (hp != null && (hp - p).distance < 8) label = o;
        case 'line':
          final end = o.t2 ?? ctx.nowMs;
          if (end < from || o.t1 > to) continue;
          final a = Offset(g.x(ctx.bar(o.t1)), g.y(o.p1)), b = Offset(g.x(ctx.bar(min(end, ctx.nowMs))), g.y(o.t2 == null ? o.p1 : o.p2));
          canvas.drawLine(a, b, Paint()
            ..color = col
            ..strokeWidth = 1.2);
        case 'zone':
          final end = o.t2 ?? ctx.nowMs;
          if (hv == null || end < from || o.t1 > to) continue;
          final price = g.price(hv.y);
          if (hv.bar >= ctx.bar(o.t1) && hv.bar <= ctx.bar(min(end, ctx.nowMs)) && price <= max(o.p1, o.p2) && price >= min(o.p1, o.p2)) label = o;
      }
    }
    final l = label;
    if (l != null && l.label.isNotEmpty && hp != null) {
      drawText(canvas, l.label, Offset(hp.dx + 12, hp.dy - 14), ts(11, color: colorOf(l.color), w: FontWeight.w500));
    }
  }

  static void _marker(Canvas c, Offset p, String shape, Color col) {
    final fill = Paint()..color = col;
    switch (shape) {
      case 'arrow_up':
        c.drawPath(Path()
          ..moveTo(p.dx, p.dy + 3)
          ..lineTo(p.dx - 5, p.dy + 11)
          ..lineTo(p.dx + 5, p.dy + 11)
          ..close(), fill);
      case 'arrow_down':
        c.drawPath(Path()
          ..moveTo(p.dx, p.dy - 3)
          ..lineTo(p.dx - 5, p.dy - 11)
          ..lineTo(p.dx + 5, p.dy - 11)
          ..close(), fill);
      case 'cross':
        final s = Paint()
          ..color = col
          ..strokeWidth = 1.5;
        c.drawLine(p.translate(-4, -4), p.translate(4, 4), s);
        c.drawLine(p.translate(-4, 4), p.translate(4, -4), s);
      default:
        c.drawCircle(p, 3, fill);
    }
  }
}
