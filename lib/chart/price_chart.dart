import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/candles.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../util/format.dart';
import 'chart_geometry.dart';
import 'chart_layer.dart';
import 'paint_utils.dart';
import 'trades_layer.dart';
import 'volume_profile_tool.dart';
import '../practice/practice_layer.dart';

class PriceChart extends StatefulWidget {
  const PriceChart({super.key, required this.state, this.tool, this.practice});
  final AppState state;

  /// The volume profile drawing tool (drag from candle to candle; resize by the edges).
  final VolumeProfileTool? tool;

  /// A practice session's chart side: drag SL/TP/order lines, pick prices (M8).
  final PracticeChart? practice;

  @override
  State<PriceChart> createState() => _PriceChartState();
}

class _PriceChartState extends State<PriceChart> {
  ChartGeometry? _geo;
  AppState get s => widget.state;
  VolumeProfileTool? get tool => widget.tool;
  PracticeChart? get practice => widget.practice;

  // Gesture tuning. Flip the sign of [_zoomPerPx] if two-finger up/down feels inverted.
  static const _zoomPerPx = 0.004; // trackpad: fingers up (negative dy) = zoom in
  static const _wheelZoomPerPx = 0.0025; // mouse wheel: up = zoom in
  static const _axisScalePerPx = 0.006; // price axis drag: up = taller candles

  double _panAcc = 0, _zoomAcc = 1, _lastScale = 1;
  Axis? _swipeAxis;
  bool _dragAxis = false, _dragging = false, _overAxis = false, _dragTool = false, _dragPractice = false;
  DateTime _lastAxisTap = DateTime(2000);

  bool _onAxis(Offset p) {
    final g = _geo;
    return g != null && p.dx >= g.axisX && p.dy <= g.plotH;
  }

  double _anchor(Offset p) {
    final g = _geo;
    return g == null || g.plotW <= 0 ? 1 : (p.dx / g.plotW).clamp(0.0, 1.0).toDouble();
  }

  /// Horizontal scroll in (fractional) bars; positive = later in time.
  void _panBars(double bars) {
    _panAcc += bars;
    final whole = _panAcc.truncate();
    if (whole == 0) return;
    _panAcc -= whole;
    s.pan(whole);
  }

  /// Zoom by [f] (> 1 = more bars), accumulated so slow trackpad motion still moves.
  void _zoom(double f, Offset at) {
    _zoomAcc *= f;
    final target = (s.zoom * _zoomAcc).round();
    if (target == s.zoom) return;
    s.zoomAt(target / s.zoom, _anchor(at));
    _zoomAcc = 1;
  }

  void _onScroll(PointerScrollEvent e) {
    final g = _geo;
    if (g == null || !s.loaded) return;
    var dx = e.scrollDelta.dx, dy = e.scrollDelta.dy;
    if (dx == 0 && HardwareKeyboard.instance.isShiftPressed) {
      dx = dy;
      dy = 0;
    }
    if (dx.abs() > dy.abs()) {
      _panBars(dx / g.xs);
    } else if (dy != 0) {
      _zoom(exp(dy * _wheelZoomPerPx), e.localPosition);
    }
  }

  void _onSwipeStart(PointerPanZoomStartEvent e) {
    _swipeAxis = null;
    _lastScale = 1;
    _panAcc = 0;
    _zoomAcc = 1;
  }

  /// Two-finger touchpad: up/down zooms, left/right scrolls (axis locked per gesture), pinch zooms.
  void _onSwipe(PointerPanZoomUpdateEvent e) {
    final g = _geo;
    if (g == null || !s.loaded) return;
    // Global pan values: the chart isn't rotated or scaled, and `localPan` is offset by the
    // widget's position (transformed like a point), which broke the axis lock.
    final d = e.panDelta, total = e.pan;
    if (_swipeAxis == null && total.distance > 4) {
      _swipeAxis = total.dx.abs() > total.dy.abs() ? Axis.horizontal : Axis.vertical;
    }
    if (_swipeAxis == Axis.horizontal) _panBars(-d.dx / g.xs);
    if (_swipeAxis == Axis.vertical) _zoom(exp(d.dy * _zoomPerPx), e.localPosition);
    if (e.scale > 0 && e.scale != _lastScale) {
      _zoom(_lastScale / e.scale, e.localPosition);
      _lastScale = e.scale;
    }
  }

  void _onDragStart(DragStartDetails d) {
    _dragAxis = _onAxis(d.localPosition);
    final g = _geo;
    _dragPractice = !_dragAxis && g != null && (practice?.dragStart(g, d.localPosition) ?? false);
    _dragTool = !_dragAxis && !_dragPractice && g != null && (tool?.dragStart(g, d.localPosition) ?? false);
    _panAcc = 0;
    setState(() => _dragging = true);
  }

  void _onDrag(DragUpdateDetails d) {
    final g = _geo;
    if (g == null || !s.loaded) return;
    if (_dragPractice) {
      practice!.dragUpdate(g, d.localPosition);
      return;
    }
    if (_dragTool) {
      tool!.dragUpdate(g, d.localPosition);
      return;
    }
    if (_dragAxis) {
      s.scalePrice(exp(-d.delta.dy * _axisScalePerPx));
      return;
    }
    _panBars(-d.delta.dx / g.xs);
    if (d.delta.dy != 0 && g.bottom > g.top) s.shiftPrice(d.delta.dy / (g.bottom - g.top) / s.priceZoom);
  }

  void _hover(Offset p) {
    final g = _geo;
    if (g == null || !s.loaded) return;
    final axis = _onAxis(p);
    if (axis != _overAxis) setState(() => _overAxis = axis);
    if (p.dx < 0 || p.dx > g.plotW || p.dy > g.plotH) {
      s.hover.value = null;
      return;
    }
    if (!_dragging) {
      tool?.hover(g, p);
      practice?.hover(g, p);
    }
    s.hover.value = HoverInfo(g.barAt(p.dx).clamp(0, s.n - 1).toInt(), p.dy);
  }

  void _tap(Offset p) {
    final g = _geo;
    if (g == null) return;
    if (_onAxis(p)) {
      // Double-click the price axis: back to autoscale.
      final now = DateTime.now();
      if (now.difference(_lastAxisTap).inMilliseconds < 350) s.resetPriceScale();
      _lastAxisTap = now;
      return;
    }
    _hover(p);
    final h = s.hover.value;
    if (h == null) return;
    if (s.isReplay && s.selectMode) {
      s.startAt(h.bar);
      return;
    }
    if (practice?.tap(g, p) ?? false) return; // a price field waiting for a click
    if (tool?.active ?? false) {
      tool!.tap(g, p);
      return;
    }
    final cur = s.visibleCursor;
    final ctx = LayerContext(state: s, candles: s.candles!, cursor: cur, nowMs: s.nowMs);
    final hit = s.layersOn.contains('trades') ? TradesLayer.hit(g, ctx, h.bar, g.price(h.y)) : null;
    if (hit != null) {
      tool?.deselect();
    } else if (tool?.tap(g, p) ?? false) {
      return; // a volume profile was selected
    }
    if (hit != null || !s.isReplay) s.selectTrade(hit?.ticket);
  }

  void _endDrag(bool cancelled) {
    if (_dragTool) cancelled ? tool!.dragCancel() : tool!.dragEnd();
    if (_dragPractice) cancelled ? practice!.dragCancel() : practice!.dragEnd();
    _dragTool = false;
    _dragPractice = false;
    setState(() => _dragging = false);
  }

  @override
  Widget build(BuildContext context) => Listener(
        onPointerSignal: (e) {
          if (e is PointerScrollEvent) _onScroll(e);
        },
        onPointerPanZoomStart: _onSwipeStart,
        onPointerPanZoomUpdate: _onSwipe,
        child: MouseRegion(
          cursor: practice?.cursor() ??
              (practice?.p.picking != null ? SystemMouseCursors.cell : null) ??
              (_dragging
              ? (_dragAxis ? SystemMouseCursors.resizeUpDown : (_dragTool ? (tool!.drawing ? SystemMouseCursors.precise : SystemMouseCursors.resizeLeftRight) : SystemMouseCursors.grabbing))
              : (_overAxis
                  ? SystemMouseCursors.resizeUpDown
                  : (tool?.hoverEdge != null ? SystemMouseCursors.resizeLeftRight : SystemMouseCursors.precise))),
          onHover: (e) => _hover(e.localPosition),
          onExit: (_) => s.hover.value = null,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // Mouse/touch drag only: two-finger touchpad gestures are handled by the Listener above.
            supportedDevices: const {PointerDeviceKind.mouse, PointerDeviceKind.touch, PointerDeviceKind.stylus, PointerDeviceKind.invertedStylus},
            // The drag starts where the button went down, so a range starts on the pressed candle.
            dragStartBehavior: DragStartBehavior.down,
            onTapUp: (d) => _tap(d.localPosition),
            onPanStart: _onDragStart,
            onPanUpdate: _onDrag,
            onPanEnd: (_) => _endDrag(false),
            onPanCancel: () => _endDrag(true),
            child: CustomPaint(painter: ChartPainter(s, (g) => _geo = g, tool: tool, practice: practice), child: const SizedBox.expand()),
          ),
        ),
      );
}

class ChartPainter extends CustomPainter {
  ChartPainter(this.s, this.onGeometry, {this.tool, this.practice}) : super(repaint: Listenable.merge([s, s.hover, ?tool, ?practice]));
  final PracticeChart? practice;
  final AppState s;
  final VolumeProfileTool? tool;
  final void Function(ChartGeometry) onGeometry;

  @override
  void paint(Canvas canvas, Size size) {
    final c = s.candles;
    if (c == null || c.length == 0) return;
    final cur = s.visibleCursor;
    final layers = layersOf(s).where((l) => l.isOn(s)).toList();
    final g = ChartGeometry.compute(size, s, c, cur, 0);
    onGeometry(g);
    final pw = g.plotW, ph = g.plotH, ax = g.axisX;
    final gridP = Paint()..color = C.line;
    final axisStyle = ts(11, color: C.mute);
    final hv = s.hover.value;

    final pTop = g.price(0), pBot = g.price(ph), raw = (pTop - pBot) / 9;
    const steps = [0.5, 1.0, 2.0, 2.5, 5.0, 10.0, 20.0, 25.0, 50.0, 100.0, 250.0];
    final st = steps.firstWhere((x) => x >= raw, orElse: () => 500.0);
    for (var p = (pBot / st).ceil() * st; p <= pTop; p += st) {
      final y = g.y(p);
      if (y < 10 || y > ph - 6) continue;
      dashH(canvas, 0, pw, y, gridP, dash: 1, gap: 4);
      drawText(canvas, fmtPrice(p), Offset(ax + 12, y), axisStyle);
    }
    const tks = [4, 8, 16, 32, 48, 96, 192, 384, 768, 1536];
    final tk = tks.firstWhere((k) => k * g.xs >= 110, orElse: () => 3072);
    for (var i = (g.viewStart / tk).ceil() * tk; i <= g.viewStart + g.slots; i += tk) {
      final x = g.x(i);
      if (x < 20 || x > pw - 20) continue;
      dashV(canvas, x, 0, ph, gridP, dash: 1, gap: 4);
      drawText(canvas, fmtAxis(s.timeOf(i)), Offset(x, ph + 14), axisStyle, align: TextAlign.center);
    }

    final ctx = LayerContext(state: s, candles: c, cursor: cur, nowMs: s.nowMs);
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, pw, ph));
    for (final l in layers) {
      l.paintBelow(canvas, g, ctx);
    }
    _candles(canvas, g, c, cur, hv);
    for (final l in layers) {
      l.paintAbove(canvas, g, ctx);
    }
    tool?.paint(canvas, g, s);

    final lp = c.c[cur], yl = g.y(lp);
    dashH(canvas, 0, pw, yl, Paint()..color = C.gold.withOpacity(0.45), dash: 2, gap: 3);
    if (s.isReplay && !s.selectMode) {
      final x = g.x(cur) + g.xs / 2;
      canvas.drawLine(Offset(x, 0), Offset(x, ph), Paint()..color = C.gold);
    }
    if (hv != null) {
      final x = g.x(hv.bar);
      if (s.selectMode) {
        canvas.drawLine(Offset(x + g.xs / 2, 0), Offset(x + g.xs / 2, ph),
            Paint()
              ..color = C.gold
              ..strokeWidth = 1.25);
      } else {
        final cp = Paint()..color = C.mute.withOpacity(0.6);
        dashV(canvas, x, 0, ph, cp, dash: 3, gap: 3);
        dashH(canvas, 0, pw, hv.y, cp, dash: 3, gap: 3);
      }
    }
    canvas.restore();

    canvas.drawLine(Offset(ax, 0), Offset(ax, ph), gridP);
    canvas.drawLine(Offset(0, ph), Offset(size.width, ph), gridP);
    final tagStyle = ts(11, w: FontWeight.w600);
    tag(canvas, Rect.fromLTWH(ax + 4, yl - 10, ChartGeometry.axisRight - 8, 20), fmtPrice(lp), C.gold, C.bg, tagStyle);
    Rect timeRect(double x) => Rect.fromCenter(center: Offset(x, ph + 14), width: 96, height: 20);
    if (s.isReplay && !s.selectMode) {
      tag(canvas, timeRect(g.x(cur) + g.xs / 2), fmtShort(s.timeOf(cur)), C.gold, C.bg, tagStyle);
    }
    if (hv != null) {
      if (s.selectMode) {
        tag(canvas, timeRect(g.x(hv.bar)), fmtShort(s.timeOf(hv.bar)), C.gold, C.bg, tagStyle);
      } else {
        tag(canvas, Rect.fromLTWH(ax + 4, hv.y - 10, ChartGeometry.axisRight - 8, 20), fmtPrice(g.price(hv.y)), C.line, C.text, tagStyle);
        tag(canvas, timeRect(g.x(hv.bar)), fmtShort(s.timeOf(hv.bar)), C.line, C.text, tagStyle);
      }
    }
  }

  /// Monochrome: hollow up, filled down, so coloured zones carry the meaning.
  void _candles(Canvas canvas, ChartGeometry g, Candles c, int cur, HoverInfo? hv) {
    final bw = (g.xs * 0.6).clamp(1.0, 10.0);
    final kStart = max(0, g.viewStart - 1), kEnd = min(cur, g.viewStart + g.slots);
    final wick = Paint(), body = Paint(), outline = Paint()..style = PaintingStyle.stroke;
    for (var i = kStart; i <= kEnd; i++) {
      final x = g.x(i), o = c.o[i], cl = c.c[i];
      final a = (s.selectMode && hv != null && i > hv.bar) ? 0.18 : 1.0;
      wick.color = C.text.withOpacity(0.75 * a);
      canvas.drawLine(Offset(x, g.y(c.h[i])), Offset(x, g.y(c.l[i])), wick);
      final yTop = g.y(max(o, cl));
      final r = Rect.fromLTRB(x - bw / 2, yTop, x + bw / 2, max(g.y(min(o, cl)), yTop + 1));
      if (cl >= o) {
        body.color = C.bg;
        canvas.drawRect(r, body);
        outline.color = C.text.withOpacity(0.82 * a);
        canvas.drawRect(r, outline);
      } else {
        body.color = C.text.withOpacity(0.82 * a);
        canvas.drawRect(r, body);
      }
    }
  }

  @override
  bool shouldRepaint(covariant ChartPainter old) => true;
}
