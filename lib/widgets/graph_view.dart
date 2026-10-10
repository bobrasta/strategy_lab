import 'dart:async';
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../chart/paint_utils.dart';
import '../run/equity_store.dart';
import '../theme.dart';
import '../util/format.dart';
import 'common.dart';

/// One run's curve in the graph.
class GraphSeries {
  const GraphSeries({required this.store, required this.label, required this.equityColor, required this.balanceColor, this.cutMs});
  final EquityStore store;
  final String label;
  final Color equityColor, balanceColor;

  /// Replay: nothing stamped after this is drawn (the last point is the exact row at it).
  final int? cutMs;
}

/// Balance and equity (with the per-bucket equity range), and equity drawdown % below, from
/// equity.csv. Buckets are picked rows, not computed values; hover shows exact rows.
///
/// Time zoom, with the price chart's gestures: wheel or two-finger up/down zooms at the pointer,
/// sideways (or shift+wheel, or a drag) pans, double-click or "Full range" resets. A zoomed
/// window is re-bucketed from just its part of the file in a background isolate (about one
/// bucket per pixel); the whole-run buckets are drawn until that arrives.
class EquityGraph extends StatefulWidget {
  const EquityGraph({super.key, required this.series, this.showBalance = true});
  final List<GraphSeries> series;
  final bool showBalance;

  @override
  State<EquityGraph> createState() => _EquityGraphState();
}

/// Window buckets for one series: [buckets] cover the rows stamped in [from, to].
class _Fine {
  const _Fine(this.store, this.from, this.to, this.buckets);
  final EquityStore store;
  final int from, to;
  final GraphBuckets buckets;
  bool covers((int, int) v) => from <= v.$1 && to >= v.$2;
}

/// The runs' combined time span, or null when there is nothing to draw.
(int, int)? graphSpan(List<GraphSeries> series) {
  var t0 = 1 << 62, t1 = -(1 << 62);
  for (final s in series) {
    final ix = s.store.index;
    if (ix.buckets == 0) continue;
    t0 = min(t0, ix.gFirstMs.first);
    t1 = max(t1, ix.lastMs);
  }
  return t1 > t0 ? (t0, t1) : null;
}

class _EquityGraphState extends State<EquityGraph> {
  static const _minSpanMs = 2 * 3600 * 1000;
  static const _zoomPerPx = 0.004; // trackpad, as on the price chart
  static const _wheelZoomPerPx = 0.0025;

  double? _hx;
  (int, int)? _view; // null = the whole run
  final _fine = <int, _Fine>{}; // by series index
  Timer? _debounce;
  int _token = 0;
  double _plotW = 0;
  Axis? _swipeAxis;
  double _lastScale = 1;

  @override
  void didUpdateWidget(covariant EquityGraph old) {
    super.didUpdateWidget(old);
    final same = old.series.length == widget.series.length &&
        [for (var k = 0; k < old.series.length; k++) identical(old.series[k].store, widget.series[k].store)].every((x) => x);
    if (!same) {
      _view = null;
      _fine.clear();
      _debounce?.cancel();
      _token++;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _setView(double a, double b) {
    final full = graphSpan(widget.series);
    if (full == null) return;
    final (f0, f1) = full;
    final fw = (f1 - f0).toDouble();
    final w = (b - a).clamp(min(fw, _minSpanMs.toDouble()), fw);
    if (w >= fw) {
      setState(() => _view = null);
    } else {
      final v0 = a.clamp(f0.toDouble(), f1 - w);
      setState(() => _view = (v0.round(), (v0 + w).round()));
    }
    _scheduleRefine();
  }

  (int, int)? get _shown => _view ?? graphSpan(widget.series);

  /// Zoom by [f] (> 1 = a longer window) keeping the time under [px] in place.
  void _zoom(double f, double px) {
    final v = _shown;
    if (v == null || _plotW <= 0) return;
    final frac = ((px - _GraphPainter.l) / _plotW).clamp(0.0, 1.0);
    final at = v.$1 + frac * (v.$2 - v.$1), nw = (v.$2 - v.$1) * f;
    _setView(at - frac * nw, at + (1 - frac) * nw);
  }

  /// Pan by [px] pixels; positive = later in time.
  void _pan(double px) {
    final v = _view;
    if (v == null || _plotW <= 0) return;
    final d = px / _plotW * (v.$2 - v.$1);
    _setView(v.$1 + d, v.$2 + d);
  }

  void _onScroll(PointerScrollEvent e) {
    var dx = e.scrollDelta.dx, dy = e.scrollDelta.dy;
    if (dx == 0 && HardwareKeyboard.instance.isShiftPressed) {
      dx = dy;
      dy = 0;
    }
    if (dx.abs() > dy.abs()) {
      _pan(dx);
    } else if (dy != 0) {
      _zoom(exp(dy * _wheelZoomPerPx), e.localPosition.dx);
    }
  }

  void _onSwipe(PointerPanZoomUpdateEvent e) {
    final d = e.panDelta, total = e.pan;
    if (_swipeAxis == null && total.distance > 4) _swipeAxis = total.dx.abs() > total.dy.abs() ? Axis.horizontal : Axis.vertical;
    if (_swipeAxis == Axis.horizontal) _pan(-d.dx);
    if (_swipeAxis == Axis.vertical) _zoom(exp(d.dy * _zoomPerPx), e.localPosition.dx);
    if (e.scale > 0 && e.scale != _lastScale) {
      _zoom(_lastScale / e.scale, e.localPosition.dx);
      _lastScale = e.scale;
    }
  }

  void _scheduleRefine() {
    _debounce?.cancel();
    if (_view == null) return;
    _debounce = Timer(const Duration(milliseconds: 150), _refine);
  }

  /// Fetch window buckets for every series whose current buckets are too sparse for the view.
  void _refine() {
    final v = _view;
    if (v == null || _plotW <= 0) return;
    final tok = ++_token;
    final span = v.$2 - v.$1, from = v.$1 - span ~/ 4, to = v.$2 + span ~/ 4; // margin for small pans
    for (var k = 0; k < widget.series.length; k++) {
      final store = widget.series[k].store, have = _fine[k];
      final src = have != null && have.store == store && have.covers(v) ? have.buckets : store.index.graph;
      var visible = 0;
      for (var i = 0; i < src.length; i++) {
        if (src.ms[i] >= v.$1 && src.ms[i] <= v.$2) visible++;
      }
      if (src.perBucket == 1 || visible >= _plotW / 2) continue;
      store.bucketsIn(from, to, (_plotW * 1.5).round()).then((b) {
        if (!mounted || tok != _token || k >= widget.series.length || widget.series[k].store != store) return;
        setState(() => _fine[k] = _Fine(store, from, to, b));
      }, onError: (Object _) {}); // the whole-run buckets stay
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        _plotW = c.maxWidth - _GraphPainter.l - _GraphPainter.r;
        final v = _shown;
        final fine = [
          for (var k = 0; k < widget.series.length; k++)
            switch (_fine[k]) {
              final f? when v != null && _view != null && f.store == widget.series[k].store && f.covers(v) => f.buckets,
              _ => null,
            }
        ];
        // The button sits beside the gesture area, not inside it, so its taps don't wait on the
        // graph's double-click.
        return Stack(children: [
          Listener(
            onPointerSignal: (e) {
              if (e is PointerScrollEvent) _onScroll(e);
            },
            onPointerPanZoomStart: (_) {
              _swipeAxis = null;
              _lastScale = 1;
            },
            onPointerPanZoomUpdate: _onSwipe,
            child: MouseRegion(
              onHover: (e) => setState(() => _hx = e.localPosition.dx),
              onExit: (_) => setState(() => _hx = null),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                supportedDevices: const {PointerDeviceKind.mouse, PointerDeviceKind.touch, PointerDeviceKind.stylus, PointerDeviceKind.invertedStylus},
                onPanUpdate: (d) => _pan(-d.delta.dx),
                onDoubleTap: () => _setView(double.negativeInfinity, double.infinity),
                child: CustomPaint(size: Size(c.maxWidth, c.maxHeight), painter: _GraphPainter(widget.series, fine, v, widget.showBalance, _hx)),
              ),
            ),
          ),
          if (_view != null)
            Positioned(
              top: 0,
              right: 0,
              child: Row(children: [
                Text('${fmtDate(_view!.$1)} → ${fmtDate(_view!.$2)}', style: ts(11, color: C.mute)),
                const SizedBox(width: 8),
                PillButton(label: 'Full range', height: 22, fontSize: 11, onTap: () => _setView(double.negativeInfinity, double.infinity)),
              ]),
            ),
        ]);
      });
}

class GraphPt {
  const GraphPt(this.ms, this.bal, this.eq, this.lo, this.hi, this.ddp);
  final int ms;
  final double bal, eq, lo, hi, ddp;
}

/// The points drawn for [s]: buckets (the whole-run ones unless [buckets] is given) that end by
/// its cut, then the exact row at the cut. With a window [from, to], the buckets in it plus the
/// nearest one on each side, so the lines run to the edges.
List<GraphPt> graphPoints(GraphSeries s, {GraphBuckets? buckets, int? from, int? to}) {
  final g = buckets ?? s.store.index.graph, cut = s.cutMs;
  final out = <GraphPt>[];
  GraphPt? before;
  for (var i = 0; i < g.length; i++) {
    final ms = g.ms[i];
    if (cut != null && ms > cut) break;
    final p = GraphPt(ms, g.balance[i], g.equity[i], g.eqMin[i], g.eqMax[i], g.ddPct[i]);
    if (from != null && ms < from) {
      before = p;
      continue;
    }
    out.add(p);
    if (to != null && ms > to) break;
  }
  if (before != null) out.insert(0, before);
  if (cut != null) {
    final r = s.store.at(cut);
    if (r != null && (out.isEmpty || r.ms > out.last.ms)) out.add(GraphPt(r.ms, r.balance, r.equity, r.equityMin, r.equity, r.drawdownPct ?? 0));
  }
  return out;
}

/// Time-axis labels for [t0, t1] over [w] pixels, at least ~90 px apart: hours, days, months or
/// years, on UTC boundaries.
List<(int, String)> timeTicks(int t0, int t1, double w) {
  const hour = 3600 * 1000, day = 24 * hour;
  final minGap = 90 * (t1 - t0) / max(1.0, w);
  final out = <(int, String)>[];
  for (final step in const [hour, 2 * hour, 3 * hour, 6 * hour, 12 * hour, day, 2 * day, 7 * day]) {
    if (step < minGap) continue;
    for (var ms = (t0 ~/ step + 1) * step; ms < t1; ms += step) {
      out.add((ms, fmtAxis(DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true))));
    }
    return out;
  }
  final months = const [1, 2, 3, 6, 12, 24, 60].firstWhere((m) => m * 30.4 * day >= minGap, orElse: () => 120);
  final d0 = DateTime.fromMillisecondsSinceEpoch(t0, isUtc: true);
  for (var d = DateTime.utc(d0.year, d0.month + 1); d.millisecondsSinceEpoch < t1; d = DateTime.utc(d.year, d.month + 1)) {
    if ((d.year * 12 + d.month - 1) % months != 0) continue;
    out.add((d.millisecondsSinceEpoch, months >= 12 ? '${d.year}' : '${d.year}-${d.month.toString().padLeft(2, '0')}'));
  }
  return out;
}

class _GraphPainter extends CustomPainter {
  _GraphPainter(this.series, this.fine, this.view, this.showBalance, this.hx);
  final List<GraphSeries> series;
  final List<GraphBuckets?> fine; // window buckets per series, or null for the whole-run ones
  final (int, int)? view;
  final bool showBalance;
  final double? hx;

  static const l = 8.0, r = 76.0, t = 26.0, b = 22.0;

  @override
  void paint(Canvas c, Size size) {
    final v = view;
    if (series.isEmpty || v == null) return;
    final (t0, t1) = v;
    final pts = [for (var k = 0; k < series.length; k++) graphPoints(series[k], buckets: fine[k], from: t0, to: t1)];
    // Autoscale to the points inside the window (all of them if none is).
    var lo = double.infinity, hi = -double.infinity, dd = 0.0;
    for (final inside in [true, false]) {
      for (final ps in pts) {
        for (final p in ps) {
          if (inside && (p.ms < t0 || p.ms > t1)) continue;
          lo = min(lo, min(p.lo, p.bal));
          hi = max(hi, max(p.hi, p.bal));
          dd = max(dd, p.ddp);
        }
      }
      if (lo.isFinite) break;
    }
    if (!lo.isFinite) return;
    if (hi - lo < 1) {
      hi += 0.5;
      lo -= 0.5;
    }
    final pad = (hi - lo) * 0.06;
    lo -= pad;
    hi += pad;
    final w = size.width - l - r, h = size.height - t - b;
    final hTop = h * 0.72, ddTop = t + hTop + 10, hDd = h - hTop - 10;
    final ddMax = max(1.0, dd * 1.1);
    double x(int ms) => l + (ms - t0) / (t1 - t0) * w;
    double y(double v) => t + (hi - v) / (hi - lo) * hTop;
    double yd(double p) => ddTop + p / ddMax * hDd;

    final grid = Paint()..color = C.line;
    final axis = ts(10.5, color: C.mute);
    // money grid
    final raw = (hi - lo) / 5;
    final mag = pow(10, (log(raw) / ln10).floor()).toDouble();
    final step = [1, 2, 2.5, 5, 10].map((m) => m * mag).firstWhere((s) => s >= raw, orElse: () => 10 * mag);
    for (var v = (lo / step).ceil() * step; v <= hi; v += step) {
      dashH(c, l, l + w, y(v), grid, dash: 1, gap: 4);
      drawText(c, fmtMoney(v.toDouble()).replaceAll('.00', ''), Offset(l + w + 8, y(v)), axis);
    }
    // drawdown grid
    c.drawLine(Offset(l, ddTop), Offset(l + w, ddTop), grid);
    drawText(c, '0%', Offset(l + w + 8, ddTop), axis);
    drawText(c, '-${ddMax.toStringAsFixed(ddMax < 10 ? 1 : 0)}%', Offset(l + w + 8, ddTop + hDd), axis);
    drawText(c, 'EQUITY DRAWDOWN', Offset(l + 4, ddTop + 9), ts(10, color: C.mute, ls: 0.8));
    for (final (ms, label) in timeTicks(t0, t1, w)) {
      final xx = x(ms);
      dashV(c, xx, t, t + h, grid, dash: 1, gap: 4);
      drawText(c, label, Offset(xx, size.height - 9), axis, align: TextAlign.center);
    }

    c.save();
    c.clipRect(Rect.fromLTRB(l, 0, l + w, t + h + 1));
    for (var k = 0; k < series.length; k++) {
      final s = series[k], ps = pts[k];
      if (ps.isEmpty) continue;
      final band = Paint()
        ..color = s.equityColor.withOpacity(0.28)
        ..strokeWidth = 1;
      for (final p in ps) {
        if (p.hi - p.lo > 0) c.drawLine(Offset(x(p.ms), y(p.hi)), Offset(x(p.ms), y(p.lo)), band);
      }
      Path line(double Function(GraphPt) f) {
        final path = Path()..moveTo(x(ps.first.ms), f(ps.first));
        for (final p in ps.skip(1)) {
          path.lineTo(x(p.ms), f(p));
        }
        return path;
      }

      if (showBalance) {
        c.drawPath(line((p) => y(p.bal)), Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = s.balanceColor);
      }
      c.drawPath(line((p) => y(p.eq)), Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..color = s.equityColor);
      // drawdown: a filled area for one run, lines when comparing
      final ddPath = line((p) => yd(p.ddp));
      if (series.length == 1) {
        final fill = Path.from(ddPath)
          ..lineTo(x(ps.last.ms), ddTop)
          ..lineTo(x(ps.first.ms), ddTop)
          ..close();
        c.drawPath(fill, Paint()..color = C.red.withOpacity(0.35));
      } else {
        c.drawPath(ddPath, Paint()
          ..style = PaintingStyle.stroke
          ..color = s.equityColor.withOpacity(0.8));
      }
    }

    c.restore();

    // legend
    var lx = l + 4.0;
    for (final s in series) {
      for (final (label, col) in [if (showBalance) ('${s.label} balance', s.balanceColor), ('${s.label} equity', s.equityColor)]) {
        c.drawLine(Offset(lx, 10), Offset(lx + 14, 10), Paint()
          ..color = col
          ..strokeWidth = 2);
        final tp = TextPainter(text: TextSpan(text: label.trim(), style: ts(11, color: C.mute)), textDirection: TextDirection.ltr)..layout();
        tp.paint(c, Offset(lx + 18, 10 - tp.height / 2));
        lx += 18 + tp.width + 16;
      }
    }

    // hover: exact rows at the nearest bucket end
    final hxv = hx;
    if (hxv != null && hxv >= l && hxv <= l + w) {
      dashV(c, hxv, t, t + h, Paint()..color = C.mute.withOpacity(0.6), dash: 3, gap: 3);
      final lines = <(String, Color)>[];
      String? when;
      for (var k = 0; k < series.length; k++) {
        final ps = pts[k];
        if (ps.isEmpty) continue;
        final target = t0 + ((hxv - l) / w * (t1 - t0)).round();
        if (target < ps.first.ms) continue;
        var best = ps.first;
        for (final p in ps) {
          if (p.ms > target) break;
          best = p;
        }
        final row = series[k].store.at(best.ms);
        if (row == null) continue;
        when ??= formatTimeShort(row.ms);
        final pre = series.length > 1 ? '${series[k].label}  ' : '';
        lines.add(('${pre}balance ${fmtMoney(row.balance)} · equity ${fmtMoney(row.equity)}'
            '${row.drawdownPct == null ? '' : ' · DD ${row.drawdownPct!.toStringAsFixed(2)}%'}', series[k].equityColor));
      }
      if (when != null) {
        final texts = [(when, C.mute), ...lines];
        final tps = [for (final (s, col) in texts) TextPainter(text: TextSpan(text: s, style: ts(11.5, color: col == C.mute ? C.mute : C.text)), textDirection: TextDirection.ltr)..layout()];
        final bw = tps.map((p) => p.width).reduce(max) + 20, bh = tps.fold<double>(0, (a, p) => a + p.height + 3) + 14;
        var bx = hxv + 12;
        if (bx + bw > l + w) bx = hxv - 12 - bw;
        final rect = RRect.fromRectAndRadius(Rect.fromLTWH(bx, t + 6, bw, bh), const Radius.circular(10));
        c.drawRRect(rect, Paint()..color = C.panel.withOpacity(0.95));
        c.drawRRect(rect, Paint()
          ..style = PaintingStyle.stroke
          ..color = C.line);
        var yy = t + 13;
        for (final p in tps) {
          p.paint(c, Offset(bx + 10, yy));
          yy += p.height + 3;
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GraphPainter old) => true;
}

String formatTimeShort(int ms) => fmtFull(DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true));
