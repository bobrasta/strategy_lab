import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../data/candles.dart';
import '../data/events.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../util/format.dart';
import 'chart_geometry.dart';
import 'chart_layer.dart';
import 'paint_utils.dart';

class PriceChart extends StatefulWidget {
  const PriceChart({super.key, required this.state});
  final AppState state;

  @override
  State<PriceChart> createState() => _PriceChartState();
}

class _PriceChartState extends State<PriceChart> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100), value: 1);
  ChartGeometry? _geo;
  AppState get s => widget.state;

  @override
  void initState() {
    super.initState();
    s.pulseTick.addListener(_onPulse);
  }

  @override
  void dispose() {
    s.pulseTick.removeListener(_onPulse);
    _pulse.dispose();
    super.dispose();
  }

  void _onPulse() => _pulse.forward(from: 0);

  void _hover(Offset p) {
    final g = _geo;
    if (g == null || !s.loaded) return;
    if (p.dx < 0 || p.dx > g.plotW || p.dy > g.plotH) {
      s.hover.value = null;
      return;
    }
    s.hover.value = HoverInfo(g.barAt(p.dx).clamp(0, s.n - 1).toInt(), p.dy);
  }

  void _tap(Offset p) {
    final g = _geo;
    if (g == null) return;
    _hover(p);
    final h = s.hover.value;
    if (h == null) return;
    if (s.isReplay && s.selectMode) {
      s.startAt(h.bar);
      return;
    }
    final cur = s.visibleCursor, price = g.price(h.y);
    Zone? hit;
    for (final z in s.zones) {
      if (z.formed > cur) continue;
      final end = cur >= z.end ? z.end : cur;
      if (h.bar >= z.start && h.bar <= end && price >= z.ev.bottom && price <= z.ev.top) {
        hit = z;
        break;
      }
    }
    if (hit != null || !s.isReplay) s.select(hit?.ev.id);
  }

  @override
  Widget build(BuildContext context) => Listener(
        onPointerSignal: (e) {
          if (e is PointerScrollEvent) {
            final d = e.scrollDelta.dy != 0 ? e.scrollDelta.dy : e.scrollDelta.dx;
            s.pan(d.sign.toInt() * max(2, (s.zoom * 0.04).round()));
          }
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.precise,
          onHover: (e) => _hover(e.localPosition),
          onExit: (_) => s.hover.value = null,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) => _tap(d.localPosition),
            child: CustomPaint(painter: ChartPainter(s, _pulse, (g) => _geo = g), child: const SizedBox.expand()),
          ),
        ),
      );
}

class ChartPainter extends CustomPainter {
  ChartPainter(this.s, this.pulse, this.onGeometry) : super(repaint: Listenable.merge([s, s.hover, pulse]));
  final AppState s;
  final Animation<double> pulse;
  final void Function(ChartGeometry) onGeometry;

  @override
  void paint(Canvas canvas, Size size) {
    final c = s.candles;
    if (c == null || c.length == 0) return;
    final cur = s.visibleCursor;
    final layers = chartLayers.where((l) => l.available && s.layersOn.contains(l.id)).toList();
    final dock = layers.fold<double>(0, (a, l) => a + l.dockedRightWidth);
    final g = ChartGeometry.compute(size, s, c, cur, dock);
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

    // M1 drill-down: faint boundaries of the events' timeframe candles.
    if (s.drill != null) {
      final em = tfMinutes(s.eventsTf ?? 'M15') * 60000;
      final bp = Paint()..color = C.line;
      final last = min(c.length - 1, g.viewStart + g.slots);
      for (var i = max(0, g.viewStart); i <= last; i++) {
        if (c.t[i] % em == 0) {
          final x = g.x(i) - g.xs / 2;
          canvas.drawLine(Offset(x, 0), Offset(x, ph), bp);
        }
      }
    }

    final ctx = LayerContext(state: s, candles: c, cursor: cur, pulse: 1 - pulse.value);
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, pw, ph));
    for (final l in layers) {
      l.paintBelow(canvas, g, ctx);
    }
    _candles(canvas, g, c, cur, hv);
    final pk = s.peek;
    if (pk != null && pk < c.length) {
      // Hidden first-touch bar: only its open is shown until the prediction is made.
      final x = g.x(pk), y = g.y(c.o[pk]), w = (g.xs * 0.6).clamp(1.0, 10.0) + 6;
      canvas.drawLine(Offset(x - w / 2, y), Offset(x + w / 2, y),
          Paint()
            ..color = C.text
            ..strokeWidth = 1.5);
    }
    for (final l in layers) {
      l.paintAbove(canvas, g, ctx);
    }

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
