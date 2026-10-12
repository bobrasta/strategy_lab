import 'dart:math';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart' show SystemMouseCursors, MouseCursor;

import '../chart/chart_geometry.dart';
import '../chart/chart_layer.dart';
import '../chart/paint_utils.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../util/format.dart';
import 'practice_state.dart';

/// A draggable horizontal level: the position's SL/TP, or a pending order's price/SL/TP (MT5 lets you
/// drag these on the chart to modify them).
class PracticeLevel {
  const PracticeLevel(this.kind, this.price, {this.order});
  final String kind; // sl, tp (position) or price, osl, otp (order)
  final double price;
  final PracticeOrder? order;
  String get label => switch (kind) { 'sl' || 'osl' => 'SL', 'tp' || 'otp' => 'TP', _ => order?.label ?? '' };
}

/// The chart side of a practice session: drags of SL/TP/order lines and price picking. Its changes
/// repaint the chart.
class PracticeChart extends ChangeNotifier {
  PracticeChart(this.p) {
    p.addListener(notifyListeners);
  }
  final PracticeState p;

  PracticeLevel? hovered, dragging;
  double? dragPrice;

  /// The levels that can be dragged now: only at the newest point reached, while trading is possible.
  List<PracticeLevel> levels() {
    if (!p.canTrade) return const [];
    final pos = p.position;
    return [
      if (pos != null && pos.sl > 0) PracticeLevel('sl', pos.sl),
      if (pos != null && pos.tp > 0) PracticeLevel('tp', pos.tp),
      for (final o in p.orders) ...[
        PracticeLevel('price', o.price, order: o),
        if (o.sl > 0) PracticeLevel('osl', o.sl, order: o),
        if (o.tp > 0) PracticeLevel('otp', o.tp, order: o),
      ],
    ];
  }

  PracticeLevel? levelAt(ChartGeometry g, Offset at) {
    if (at.dx < 0 || at.dx > g.plotW || at.dy > g.plotH) return null;
    PracticeLevel? best;
    var bestD = 6.0;
    for (final l in levels()) {
      final d = (g.y(l.price) - at.dy).abs();
      if (d <= bestD) {
        best = l;
        bestD = d;
      }
    }
    return best;
  }

  void hover(ChartGeometry g, Offset at) {
    final l = levelAt(g, at);
    if (l?.kind != hovered?.kind || l?.order?.ticket != hovered?.order?.ticket) {
      hovered = l;
      notifyListeners();
    }
  }

  MouseCursor? cursor() => dragging != null || hovered != null ? SystemMouseCursors.resizeUpDown : null;

  bool dragStart(ChartGeometry g, Offset at) {
    final l = levelAt(g, at);
    if (l == null) return false;
    dragging = l;
    dragPrice = l.price;
    notifyListeners();
    return true;
  }

  void dragUpdate(ChartGeometry g, Offset at) {
    dragPrice = g.price(at.dy);
    notifyListeners();
  }

  /// Sends the modification (the engine checks it and may refuse with a retcode).
  void dragEnd() {
    final l = dragging, v = dragPrice;
    dragging = null;
    dragPrice = null;
    notifyListeners();
    if (l == null || v == null || (v - l.price).abs() < 1e-9) return;
    final px = double.parse(PracticeState.priceText(v));
    final pos = p.position, o = l.order;
    switch (l.kind) {
      case 'sl':
        if (pos != null) p.modifyPosition(px, pos.tp);
      case 'tp':
        if (pos != null) p.modifyPosition(pos.sl, px);
      case 'price':
        p.modifyOrder(o!, price: px);
      case 'osl':
        p.modifyOrder(o!, sl: px);
      case 'otp':
        p.modifyOrder(o!, tp: px);
    }
  }

  void dragCancel() {
    dragging = null;
    dragPrice = null;
    notifyListeners();
  }

  /// A click on the chart: fills the price field waiting for one. True when used.
  bool tap(ChartGeometry g, Offset at) {
    if (p.picking == null || at.dy > g.plotH) return false;
    p.pickPrice(g.price(at.dy));
    return true;
  }

  @override
  void dispose() {
    p.removeListener(notifyListeners);
    super.dispose();
  }
}

/// The practice trades on the chart: entries and exits as of the cursor; the open position (entry, SL,
/// TP) and pending orders only at the newest point reached, never before (they are later than the cursor).
class PracticeLayer extends ChartLayer {
  PracticeLayer(this.p, this.drag);
  final PracticeState p;
  final PracticeChart drag;

  @override
  String get id => 'practice';
  @override
  String get label => 'Practice';
  @override
  String get description => 'Your practice trades, position and orders';

  @override
  bool isOn(AppState s) => p.active;

  @override
  void paintAbove(Canvas canvas, ChartGeometry g, LayerContext ctx) {
    final c = ctx.candles, now = ctx.nowMs, barMs = c.minutes * 60000;
    double? xOf(int ms) {
      final i = c.barAt(ms);
      return i < 0 ? null : g.x(i) - g.xs / 2 + g.xs * (ms - c.t[i]) / barMs;
    }

    // Closed trades: entry triangle, exit dot, a dotted line between, as far as the cursor.
    for (final t in p.trades) {
      if (t.openMs > now) continue;
      final xo = xOf(t.openMs);
      if (xo == null) continue;
      final col = t.buy ? C.blue : C.amber;
      _triangle(canvas, Offset(xo, g.y(t.openPrice)), t.buy, col);
      if (t.closeMs <= now) {
        final xc = xOf(t.closeMs);
        if (xc == null) continue;
        final res = t.net >= 0 ? C.green : C.red;
        dashLine(canvas, Offset(xo, g.y(t.openPrice)), Offset(xc, g.y(t.closePrice)), Paint()..color = res.withOpacity(0.8));
        canvas.drawCircle(Offset(xc, g.y(t.closePrice)), 3.5, Paint()..color = res);
      }
    }
    if (!p.atHead) {
      // Looking back: the open position's entry, if it is already in the past; no levels or orders.
      final pos = p.position;
      if (pos != null && pos.openMs <= now) {
        final x = xOf(pos.openMs);
        if (x != null) _triangle(canvas, Offset(x, g.y(pos.priceOpen)), pos.buy, pos.buy ? C.blue : C.amber);
      }
      return;
    }

    final st = ts(11, w: FontWeight.w600);
    void level(double price, Color col, String text, {bool dashed = false, bool hot = false}) {
      final y = g.y(price);
      final paint = Paint()
        ..color = col.withOpacity(hot ? 1 : 0.85)
        ..strokeWidth = hot ? 1.6 : 1;
      if (dashed) {
        dashH(canvas, 0, g.plotW, y, paint, dash: 5, gap: 4);
      } else {
        canvas.drawLine(Offset(0, y), Offset(g.plotW, y), paint);
      }
      // on the left: the right of the chart is often under the open drawer
      final w = text.length * 6.6 + 14;
      tag(canvas, Rect.fromLTWH(8, y - 10, w, 20), text, col, C.bg, st);
    }

    bool hot(String kind, [PracticeOrder? o]) {
      final h = drag.dragging ?? drag.hovered;
      return h != null && h.kind == kind && h.order?.ticket == o?.ticket;
    }

    final pos = p.position;
    if (pos != null) {
      final x = xOf(pos.openMs);
      if (x != null) _triangle(canvas, Offset(x, g.y(pos.priceOpen)), pos.buy, pos.buy ? C.blue : C.amber);
      level(pos.priceOpen, C.blue, '${pos.buy ? 'Buy' : 'Sell'} ${pos.volume.toStringAsFixed(2)}  ${fmtMoneySigned(pos.profit)}');
      if (pos.sl > 0) level(pos.sl, C.red, 'SL ${fmtPrice(pos.sl)}', hot: hot('sl'));
      if (pos.tp > 0) level(pos.tp, C.green, 'TP ${fmtPrice(pos.tp)}', hot: hot('tp'));
    }
    for (final o in p.orders) {
      level(o.price, C.gold, '${o.label} ${o.volume.toStringAsFixed(2)} @ ${fmtPrice(o.price)}', dashed: true, hot: hot('price', o));
      if (o.sl > 0) level(o.sl, C.red.withOpacity(0.7), 'SL #${o.ticket}', dashed: true, hot: hot('osl', o));
      if (o.tp > 0) level(o.tp, C.green.withOpacity(0.7), 'TP #${o.ticket}', dashed: true, hot: hot('otp', o));
    }
    final d = drag.dragging, v = drag.dragPrice;
    if (d != null && v != null) {
      final col = d.kind.contains('sl') ? C.red : (d.kind.contains('tp') ? C.green : C.gold);
      level(v, col, '${d.label} → ${PracticeState.priceText(v)}', hot: true);
    }
  }

  static void _triangle(Canvas canvas, Offset at, bool up, Color col) {
    const s = 6.0;
    final path = Path();
    if (up) {
      path
        ..moveTo(at.dx, at.dy + 2)
        ..lineTo(at.dx - s, at.dy + 2 + s * 1.4)
        ..lineTo(at.dx + s, at.dy + 2 + s * 1.4);
    } else {
      path
        ..moveTo(at.dx, at.dy - 2)
        ..lineTo(at.dx - s, at.dy - 2 - s * 1.4)
        ..lineTo(at.dx + s, at.dy - 2 - s * 1.4);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = col);
  }

  /// A dotted segment.
  static void dashLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    final len = (b - a).distance;
    if (len <= 0) return;
    final dir = (b - a) / len;
    for (var d = 0.0; d < len; d += 6) {
      canvas.drawLine(a + dir * d, a + dir * min(len, d + 3), paint);
    }
  }
}
