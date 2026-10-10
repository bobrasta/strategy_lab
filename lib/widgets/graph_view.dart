import 'dart:math';

import 'package:flutter/material.dart';

import '../chart/paint_utils.dart';
import '../run/equity_store.dart';
import '../theme.dart';
import '../util/format.dart';

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
class EquityGraph extends StatefulWidget {
  const EquityGraph({super.key, required this.series, this.showBalance = true});
  final List<GraphSeries> series;
  final bool showBalance;

  @override
  State<EquityGraph> createState() => _EquityGraphState();
}

class _EquityGraphState extends State<EquityGraph> {
  double? _hx;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, c) => MouseRegion(
          onHover: (e) => setState(() => _hx = e.localPosition.dx),
          onExit: (_) => setState(() => _hx = null),
          child: CustomPaint(size: Size(c.maxWidth, c.maxHeight), painter: _GraphPainter(widget.series, widget.showBalance, _hx)),
        ),
      );
}

class GraphPt {
  const GraphPt(this.ms, this.bal, this.eq, this.lo, this.hi, this.ddp);
  final int ms;
  final double bal, eq, lo, hi, ddp;
}

/// The points drawn for [s]: buckets that end by its cut, then the exact row at the cut.
List<GraphPt> graphPoints(GraphSeries s) {
  final ix = s.store.index, cut = s.cutMs;
  final out = <GraphPt>[];
  for (var i = 0; i < ix.buckets; i++) {
    if (cut != null && ix.gMs[i] > cut) break;
    out.add(GraphPt(ix.gMs[i], ix.gBalance[i], ix.gEquity[i], ix.gEqMin[i], ix.gEqMax[i], ix.gDdPct[i]));
  }
  if (cut != null) {
    final r = s.store.at(cut);
    if (r != null && (out.isEmpty || r.ms > out.last.ms)) out.add(GraphPt(r.ms, r.balance, r.equity, r.equityMin, r.equity, r.drawdownPct ?? 0));
  }
  return out;
}

class _GraphPainter extends CustomPainter {
  _GraphPainter(this.series, this.showBalance, this.hx);
  final List<GraphSeries> series;
  final bool showBalance;
  final double? hx;

  static const l = 8.0, r = 76.0, t = 26.0, b = 22.0;

  @override
  void paint(Canvas c, Size size) {
    if (series.isEmpty) return;
    final pts = [for (final s in series) graphPoints(s)];
    // Time span: the runs' full spans (only the time axis; data stops at the cut).
    var t0 = 1 << 62, t1 = -(1 << 62);
    for (final s in series) {
      final ix = s.store.index;
      if (ix.buckets == 0) continue;
      t0 = min(t0, ix.gFirstMs.first);
      t1 = max(t1, ix.lastMs);
    }
    if (t1 <= t0) return;
    var lo = double.infinity, hi = -double.infinity, dd = 0.0;
    for (final ps in pts) {
      for (final p in ps) {
        lo = min(lo, min(p.lo, p.bal));
        hi = max(hi, max(p.hi, p.bal));
        dd = max(dd, p.ddp);
      }
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
    // time labels: years, or months for short spans
    final span = Duration(milliseconds: t1 - t0);
    final d0 = DateTime.fromMillisecondsSinceEpoch(t0, isUtc: true);
    final months = span.inDays > 900 ? 12 : (span.inDays > 300 ? 3 : 1);
    var d = DateTime.utc(d0.year, d0.month + 1);
    while (d.millisecondsSinceEpoch < t1) {
      if ((d.month - 1) % months == 0) {
        final xx = x(d.millisecondsSinceEpoch);
        dashV(c, xx, t, t + h, grid, dash: 1, gap: 4);
        drawText(c, months == 12 ? '${d.year}' : '${d.year}-${d.month.toString().padLeft(2, '0')}', Offset(xx, size.height - 9), axis, align: TextAlign.center);
      }
      d = DateTime.utc(d.year, d.month + 1);
    }

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
