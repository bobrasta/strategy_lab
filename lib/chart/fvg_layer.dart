import 'dart:math';

import 'package:flutter/painting.dart';

import '../data/events.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'chart_geometry.dart';
import 'chart_layer.dart';
import 'paint_utils.dart';

/// Optional overlay: zones from the FVG study's fvg_events.csv. Geometry and outcome come from
/// Python; only the running max-depth line is measured here, from bars ≤ cursor.
class FvgLayer extends ChartLayer {
  const FvgLayer();
  @override
  String get id => 'fvg';
  @override
  String get label => 'FVG study zones';
  @override
  String get description => 'Optional overlay from fvg_events.csv';
  @override
  bool available(AppState s) => s.events.isNotEmpty;

  static Color outcomeColor(EvOutcome o) => switch (o) {
        EvOutcome.bounce => C.green,
        EvOutcome.through => C.red,
        EvOutcome.timeout => C.mute,
      };

  /// A zone's outcome is knowable only once the cursor has reached its resolution bar
  /// (and, while the study's hold-out is locked, never for hold-out events outside replay).
  static bool outcomeKnown(Zone z, LayerContext ctx) => ctx.cursor >= z.end && !ctx.state.outcomeHidden(z.ev);

  /// Grey until [outcomeKnown], then the outcome colour.
  static Color zoneColor(Zone z, LayerContext ctx) => outcomeKnown(z, ctx) ? outcomeColor(z.ev.outcome) : C.mute;

  static Iterable<(Zone, double, double, int)> _visibleZones(ChartGeometry g, LayerContext ctx) sync* {
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
    for (final (z, x0, x1, end) in _visibleZones(g, ctx)) {
      final ev = z.ev, known = outcomeKnown(z, ctx), col = zoneColor(z, ctx);
      final r = Rect.fromLTRB(x0, g.y(ev.top), x1, g.y(ev.bottom));
      canvas.drawRect(r, Paint()..color = col.withOpacity(known ? 0.08 : 0.06));
      canvas.drawRect(r, Paint()
        ..style = PaintingStyle.stroke
        ..color = col.withOpacity(0.25));
      if (ctx.cursor >= z.touch) {
        final d = runningDepth(ctx.candles, z, min(ctx.cursor, end));
        final yd = g.y(ev.priceAtDepth(d));
        dashH(canvas, g.x(z.touch) - g.xs / 2, x1, yd, Paint()..color = C.text.withOpacity(0.35), dash: 2, gap: 2);
      }
    }
  }
}
