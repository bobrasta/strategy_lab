import 'dart:math';
import 'dart:ui';

import '../indicators/indicator_output.dart';
import '../indicators/indicators_state.dart';
import '../state/app_state.dart';
import 'chart_geometry.dart';
import 'chart_layer.dart';
import 'drawings_layer.dart';

/// Walks the points of [s] shown at [now] for bar times in [from, to] (plus one either side), in
/// time order: [point] for each value, [gap] at each EMPTY_VALUE (SPEC §7.7 display rule: for each
/// bar time the latest record stamped at or before now; nothing stamped later).
void walkPlot(PlotSeries s, int from, int to, int now, void Function(int time, double value) point, void Function() gap) {
  for (final k in s.visible(from, to, now)) {
    final v = s.value[k];
    if (v.isNaN) {
      gap();
    } else {
      point(s.time[k], v);
    }
  }
}

/// A polyline that keeps at most four vertices per pixel column (first, low, high, last), so a
/// zoomed-out M1 plot stays cheap to draw while every extreme is still on screen.
class _Polyline {
  _Polyline(this.path);
  final Path path;
  bool _started = false;
  int _col = 0, _n = 0;
  double _x = 0, _first = 0, _lo = 0, _hi = 0, _last = 0;

  void add(double x, double y) {
    final c = x.floor();
    if (_n > 0 && c == _col) {
      _lo = min(_lo, y);
      _hi = max(_hi, y);
      _last = y;
      _n++;
      return;
    }
    _flush();
    _col = c;
    _x = x;
    _first = _lo = _hi = _last = y;
    _n = 1;
  }

  void _emit(double x, double y) {
    if (_started) {
      path.lineTo(x, y);
    } else {
      path.moveTo(x, y);
      _started = true;
    }
  }

  void _flush() {
    if (_n == 0) return;
    _emit(_x, _first);
    if (_n > 1) {
      _emit(_x, _lo);
      _emit(_x, _hi);
      _emit(_x, _last);
    }
    _n = 0;
  }

  void gap() {
    _flush();
    _started = false;
  }

  void finish() => _flush();
}

/// One attached indicator: its plots as lines in their palette colour, style and width, and its
/// objects through the strategy-drawings renderer, all as of the chart's "now".
class IndicatorLayer extends ChartLayer {
  IndicatorLayer(this.instance);
  final IndicatorInstance instance;

  @override
  String get id => 'indicator:${instance.uid}';
  @override
  String get label => instance.label;
  @override
  String get description => instance.status;

  @override
  bool isOn(AppState s) => instance.visible && instance.output != null && instance.dataFile == s.candlesPath;

  @override
  void paintBelow(Canvas canvas, ChartGeometry g, LayerContext ctx) {
    final out = instance.output;
    if (out == null) return;
    final (from, to) = ctx.viewSpan(g);
    DrawingsLayer.paintZones(canvas, g, ctx, out.drawings.objectsAt(ctx.nowMs, from, to));
  }

  @override
  void paintAbove(Canvas canvas, ChartGeometry g, LayerContext ctx) {
    final out = instance.output;
    if (out == null) return;
    final (from, to) = ctx.viewSpan(g);
    final c = ctx.candles, barMs = c.minutes * 60000;
    // A plot point sits at its bar time: the centre of the chart bar opening then, or inside the
    // chart bar when the plot's timeframe is finer than the chart's.
    double? xOf(int ms) {
      final i = c.barAt(ms);
      return i < 0 ? null : g.x(i) + g.xs * (ms - c.t[i]) / barMs;
    }

    final specs = {for (final p in out.plots) p.index: p};
    final indexes = {...specs.keys, ...out.series.keys}.toList()..sort();
    for (final idx in indexes) {
      final s = out.series[idx];
      if (s == null) continue;
      final spec = specs[idx];
      final line = _Polyline(Path());
      walkPlot(s, from, to, ctx.nowMs, (t, v) {
        final x = xOf(t);
        if (x == null) {
          line.gap();
        } else {
          line.add(x, g.y(v));
        }
      }, line.gap);
      line.finish();
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..color = DrawingsLayer.colorOf(spec?.color ?? 'mute')
        ..strokeWidth = (spec?.width ?? 1).clamp(0.5, 6.0).toDouble()
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath((spec?.dashed ?? false) ? _dashed(line.path, paint.strokeWidth) : line.path, paint);
    }
    DrawingsLayer.paintObjects(canvas, g, ctx, out.drawings.objectsAt(ctx.nowMs, from, to));
  }

  static Path _dashed(Path p, double w) {
    final out = Path(), dash = 4 + w * 2, gap = 3 + w;
    for (final m in p.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += dash + gap) {
        out.addPath(m.extractPath(d, min(d + dash, m.length)), Offset.zero);
      }
    }
    return out;
  }
}
