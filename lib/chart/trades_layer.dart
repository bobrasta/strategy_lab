import 'dart:math';

import 'package:flutter/painting.dart';

import '../run/run_data.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../util/format.dart';
import 'chart_geometry.dart';
import 'chart_layer.dart';
import 'paint_utils.dart';

/// MT5 visual-tester style: entry arrows, SL/TP lines, and an entry→exit line coloured by the
/// trade's result. A trade appears at its entry bar; its exit, line colour and result only once
/// the cursor has reached the exit. Levels drawn are the initial SL/TP: later modifications are
/// only known at the exit, so drawing the final ones earlier would leak the future.
class TradesLayer extends ChartLayer {
  const TradesLayer();
  @override
  String get id => 'trades';
  @override
  String get label => 'Trades';
  @override
  String get description => 'Entries, exits and SL/TP from trades.json';
  @override
  bool available(AppState s) => s.run != null;

  static Color resultColor(Trade t) => t.net > 0 ? C.green : C.red;

  /// Trades on screen and opened by now. One position at a time, so trades in open order
  /// are also in close order and the first visible one is found by binary search.
  static Iterable<Trade> visible(ChartGeometry g, LayerContext ctx) sync* {
    final run = ctx.state.run;
    if (run == null) return;
    final (from, to) = ctx.viewSpan(g);
    final ts = run.trades;
    var lo = 0, hi = ts.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (ts[mid].closeMs < from) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    final last = min(to, ctx.nowMs);
    for (var i = lo; i < ts.length && ts[i].openMs <= last; i++) {
      yield ts[i];
    }
  }

  static bool closed(Trade t, LayerContext ctx) => t.closeMs <= ctx.nowMs;

  /// The trade whose entry→exit span and price band hold the point (for clicks).
  static Trade? hit(ChartGeometry g, LayerContext ctx, int bar, double price) {
    Trade? best;
    final tol = (g.hi - g.lo) * 0.02;
    for (final t in visible(g, ctx)) {
      final a = ctx.bar(t.openMs), b = closed(t, ctx) ? ctx.bar(t.closeMs) : ctx.cursor;
      final p0 = closed(t, ctx) ? min(t.openPrice, t.closePrice) : t.openPrice, p1 = closed(t, ctx) ? max(t.openPrice, t.closePrice) : t.openPrice;
      if (bar >= a - 1 && bar <= b + 1 && price >= p0 - tol && price <= p1 + tol) best = t;
    }
    return best;
  }

  @override
  void paintBelow(Canvas canvas, ChartGeometry g, LayerContext ctx) {
    final sel = ctx.state.selectedTrade;
    for (final t in visible(g, ctx)) {
      final a = ctx.bar(t.openMs), done = closed(t, ctx);
      final b = done ? ctx.bar(t.closeMs) : ctx.cursor;
      final x0 = g.x(a) - g.xs / 2, x1 = max(g.x(b) + g.xs / 2, x0 + 6);
      final strong = sel == t.ticket || !done ? 1.0 : 0.45;
      if (t.slInitial > 0) dashH(canvas, x0, x1, g.y(t.slInitial), Paint()..color = C.red.withOpacity(0.75 * strong), dash: 4, gap: 3);
      if (t.tpInitial > 0) dashH(canvas, x0, x1, g.y(t.tpInitial), Paint()..color = C.green.withOpacity(0.75 * strong), dash: 4, gap: 3);
    }
  }

  @override
  void paintAbove(Canvas canvas, ChartGeometry g, LayerContext ctx) {
    final sel = ctx.state.selectedTrade;
    for (final t in visible(g, ctx)) {
      final isSel = sel == t.ticket, done = closed(t, ctx);
      final pe = Offset(g.x(ctx.bar(t.openMs)), g.y(t.openPrice));
      if (done) {
        final px = Offset(g.x(ctx.bar(t.closeMs)), g.y(t.closePrice));
        final col = resultColor(t);
        _dotted(canvas, pe, px, Paint()
          ..color = col.withOpacity(isSel ? 1 : 0.8)
          ..strokeWidth = isSel ? 1.6 : 1.1);
        canvas.drawCircle(px, isSel ? 4 : 3, Paint()..color = col);
        if (isSel) {
          drawText(canvas, '${t.isBuy ? 'Buy' : 'Sell'} ${t.volume} · ${fmtMoney(t.net)}${t.flags.isEmpty ? '' : ' · ${t.flags}'}',
              Offset(px.dx + 8, px.dy - 12), ts(11, color: C.gold, w: FontWeight.w500));
        }
      }
      _arrow(canvas, pe, t.isBuy, isSel ? C.gold : C.text);
    }
  }

  static void _dotted(Canvas c, Offset a, Offset b, Paint p) {
    final d = (b - a).distance;
    if (d < 1) return;
    final u = (b - a) / d;
    for (var s = 0.0; s < d; s += 6) {
      c.drawLine(a + u * s, a + u * min(s + 3, d), p);
    }
  }

  /// Buy: triangle pointing up with its tip at the price; sell: pointing down.
  static void _arrow(Canvas c, Offset at, bool up, Color col) {
    const w = 5.0, h = 7.0;
    final path = Path();
    if (up) {
      path
        ..moveTo(at.dx, at.dy)
        ..lineTo(at.dx - w, at.dy + h)
        ..lineTo(at.dx + w, at.dy + h);
    } else {
      path
        ..moveTo(at.dx, at.dy)
        ..lineTo(at.dx - w, at.dy - h)
        ..lineTo(at.dx + w, at.dy - h);
    }
    path.close();
    c.drawPath(path, Paint()..color = col);
    c.drawPath(path, Paint()
      ..style = PaintingStyle.stroke
      ..color = C.bg
      ..strokeWidth = 0.8);
  }
}
