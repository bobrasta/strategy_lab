import 'dart:math';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../data/candles.dart';
import '../indicators/indicators_state.dart';
import '../indicators/input_time.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../util/format.dart';
import 'chart_geometry.dart';
import 'drawings_layer.dart';
import 'paint_utils.dart';

/// A volume profile's range on the chart: the first and last chart bars inside [from, to).
class ProfileSpan {
  const ProfileSpan(this.instance, this.from, this.to, this.first, this.last, this.box);
  final IndicatorInstance instance;
  final int from, to, first, last;

  /// Price extent of the profile's objects as of now (null: nothing drawn yet).
  final (double, double)? box;
}

enum _Drag { none, create, left, right }

/// TradingView's / MT5's "fixed range volume profile" drawn on the chart: pick the tool, then drag
/// from one candle to another (or click the first, then the last). The range becomes a
/// `volume_profile` indicator instance with RangeFrom / RangeTo set to those candles, so the profile
/// itself is computed by the engine like any attached indicator (rule "engine computes, app
/// displays"). A profile's left and right edges can be dragged to resize it; clicking it selects
/// it, Delete removes it.
class VolumeProfileTool extends ChangeNotifier {
  VolumeProfileTool({required this.chart, required this.indicators, this.build});

  final AppState chart;
  final IndicatorsState indicators;

  /// Builds the indicator when it has no `.so` yet (LabState.buildIndicator).
  final Future<void> Function(String name)? build;

  /// The tool is picked: the next drag (or two clicks) draws a range.
  bool active = false;

  /// Click-then-click: the first candle, waiting for the second click.
  bool clicking = false;

  _Drag _drag = _Drag.none;
  int _anchor = 0, _moving = 0;

  /// The selected profile (handles shown; Delete removes it).
  IndicatorInstance? selected;

  /// The profile edge under the mouse (resize cursor).
  (IndicatorInstance, bool left)? hoverEdge;

  /// The profile being resized.
  IndicatorInstance? resizing;

  bool get drawing => _drag == _Drag.create || clicking;
  bool get busy => _drag != _Drag.none || clicking;

  /// The range being drawn or resized, as chart bars (first, last), or null.
  (int, int)? get band {
    if (_drag == _Drag.none && !clicking) return null;
    if (_drag == _Drag.left || _drag == _Drag.right) {
      final sp = _spanOf(resizing);
      if (sp == null) return null;
      return _drag == _Drag.left ? (min(_moving, sp.last), sp.last) : (sp.first, max(_moving, sp.first));
    }
    return (min(_anchor, _moving), max(_anchor, _moving));
  }

  void toggle() {
    active = !active;
    _reset();
    if (active) selected = null;
    notifyListeners();
  }

  /// Esc: cancels a range being drawn, then the tool, then the selection. False when idle.
  bool cancel() {
    if (busy || active || selected != null) {
      if (busy) {
        _reset();
      } else if (active) {
        active = false;
      } else {
        selected = null;
      }
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Delete: removes the selected profile.
  bool deleteSelected() {
    final s = selected;
    if (s == null) return false;
    selected = null;
    if (!s.removed) indicators.remove(s);
    notifyListeners();
    return true;
  }

  void _reset() {
    _drag = _Drag.none;
    clicking = false;
    resizing = null;
  }

  // ── ranges of the attached profiles ────────────────────────────────
  final Set<String> _schemaAsked = {};

  /// [from, to) of a volume_profile instance: its RangeFrom / RangeTo inputs, or the defaults.
  (int, int)? rangeOf(IndicatorInstance i) {
    if (i.name != kVolumeProfile) return null;
    final sc = indicators.schemaOf(i.name);
    if (sc == null && (!i.inputs.containsKey('RangeFrom') || !i.inputs.containsKey('RangeTo')) && _schemaAsked.add(i.name)) {
      indicators.loadSchema(i.name).then((_) => notifyListeners());
    }
    String? v(String k) => i.inputs[k] ?? sc?.inputs.where((s) => s.name == k).firstOrNull?.def;
    final f = parseInputTime(v('RangeFrom')), t = parseInputTime(v('RangeTo'));
    return f == null || t == null || t <= f ? null : (f, t);
  }

  ProfileSpan? _spanOf(IndicatorInstance? i) {
    final c = chart.candles;
    if (i == null || c == null || c.length == 0 || i.removed) return null;
    final r = rangeOf(i);
    if (r == null) return null;
    final (from, to) = r;
    final first = c.lowerBound(from), last = c.barAt(to - 1);
    if (first > last || first >= c.length || last < 0) return null;
    (double, double)? box;
    final out = i.output;
    if (out != null && i.visible && i.dataFile == chart.candlesPath) {
      var lo = double.infinity, hi = -double.infinity;
      for (final o in out.drawings.objectsAt(chart.nowMs, from, to)) {
        for (final p in [o.p1, if (o.kind != 'marker') o.p2]) {
          lo = min(lo, p);
          hi = max(hi, p);
        }
      }
      if (lo <= hi) box = (lo, hi);
    }
    return ProfileSpan(i, from, to, first, last, box);
  }

  /// Every attached volume profile with a range on this chart, later ones on top.
  List<ProfileSpan> spans() => [for (final i in indicators.instances) ?_spanOf(i)];

  // ── geometry ───────────────────────────────────────────────────────
  static const _edgePx = 6.0, _boxPadPx = 10.0;

  static double leftX(ChartGeometry g, int bar) => g.x(bar) - g.xs / 2;
  static double rightX(ChartGeometry g, int bar) => g.x(bar) + g.xs / 2;

  bool _inBox(ChartGeometry g, ProfileSpan sp, double y) {
    final b = sp.box;
    return b != null && y >= g.y(b.$2) - _boxPadPx && y <= g.y(b.$1) + _boxPadPx;
  }

  /// The edge of a drawn profile at [p] (topmost profile first).
  (IndicatorInstance, bool left)? edgeAt(ChartGeometry g, Offset p) {
    for (final sp in spans().reversed) {
      if (!_inBox(g, sp, p.dy)) continue;
      if ((p.dx - leftX(g, sp.first)).abs() <= _edgePx) return (sp.instance, true);
      if ((p.dx - rightX(g, sp.last)).abs() <= _edgePx) return (sp.instance, false);
    }
    return null;
  }

  ProfileSpan? _hit(ChartGeometry g, Offset p) {
    for (final sp in spans().reversed) {
      if (_inBox(g, sp, p.dy) && p.dx >= leftX(g, sp.first) - _edgePx && p.dx <= rightX(g, sp.last) + _edgePx) return sp;
    }
    return null;
  }

  /// The last bar a range may reach: the replay cursor (no future), else the last bar.
  int _maxBar() => chart.isReplay ? chart.visibleCursor : chart.n - 1;
  int _clamp(int bar) => bar.clamp(0, max(0, _maxBar())).toInt();

  // ── gestures (PriceChart) ──────────────────────────────────────────
  void hover(ChartGeometry g, Offset p) {
    if (clicking) {
      final b = _clamp(g.barAt(p.dx));
      if (b != _moving) {
        _moving = b;
        notifyListeners();
      }
      return;
    }
    final e = active ? null : edgeAt(g, p);
    if (e?.$1 != hoverEdge?.$1 || e?.$2 != hoverEdge?.$2) {
      hoverEdge = e;
      notifyListeners();
    }
  }

  /// A drag starting at [p]: draws a range (tool picked) or resizes a profile (on its edge).
  /// False: not ours (the chart pans).
  bool dragStart(ChartGeometry g, Offset p) {
    if (!chart.loaded || chart.selectMode) return false;
    if (active) {
      clicking = false;
      _drag = _Drag.create;
      _anchor = _moving = _clamp(g.barAt(p.dx));
      notifyListeners();
      return true;
    }
    final e = edgeAt(g, p);
    if (e == null) return false;
    resizing = e.$1;
    selected = e.$1;
    _drag = e.$2 ? _Drag.left : _Drag.right;
    _moving = _clamp(g.barAt(p.dx));
    notifyListeners();
    return true;
  }

  void dragUpdate(ChartGeometry g, Offset p) {
    final b = _clamp(g.barAt(p.dx));
    if (b == _moving) return;
    _moving = b;
    notifyListeners();
  }

  void dragEnd() {
    switch (_drag) {
      case _Drag.create:
        _commitNew(min(_anchor, _moving), max(_anchor, _moving));
      case _Drag.left || _Drag.right:
        _commitResize();
      case _Drag.none:
        break;
    }
    _reset();
    notifyListeners();
  }

  void dragCancel() {
    _reset();
    notifyListeners();
  }

  /// A click at [p]. True when the tool used it (click-then-click drawing, selecting a profile).
  bool tap(ChartGeometry g, Offset p) {
    if (!chart.loaded || chart.selectMode) return false;
    if (active) {
      final b = _clamp(g.barAt(p.dx));
      if (!clicking) {
        clicking = true;
        _anchor = _moving = b;
      } else {
        _commitNew(min(_anchor, b), max(_anchor, b));
        _reset();
      }
      notifyListeners();
      return true;
    }
    final sp = _hit(g, p);
    if (sp?.instance != selected) {
      selected = sp?.instance;
      notifyListeners();
    }
    return sp != null;
  }

  /// Clears the selection (a click elsewhere, e.g. on a trade).
  void deselect() {
    if (selected == null) return;
    selected = null;
    notifyListeners();
  }

  int _barEnd(Candles c, int bar) => c.t[bar] + c.minutes * 60000;

  void _commitNew(int first, int last) {
    final c = chart.candles;
    if (c == null || first < 0 || last >= c.length) return;
    final i = indicators.addProfile(c.t[first], _barEnd(c, last));
    active = false;
    selected = i;
    if (indicators.infoOf(kVolumeProfile)?.status == 'not_built') build?.call(kVolumeProfile);
  }

  void _commitResize() {
    final c = chart.candles, sp = _spanOf(resizing);
    if (c == null || sp == null) return;
    var (from, to) = (sp.from, sp.to);
    if (_drag == _Drag.left) {
      from = c.t[min(_moving, sp.last)];
    } else {
      to = _barEnd(c, max(_moving, sp.first));
    }
    if (from != sp.from || to != sp.to) indicators.setProfileRange(sp.instance, from, to);
  }

  // ── painting (ChartPainter, inside the plot clip) ──────────────────
  void paint(Canvas canvas, ChartGeometry g, AppState s) {
    final accent = DrawingsLayer.colorOf('blue');
    final ph = g.plotH;
    final b = band;
    if (b != null && s.candles != null) {
      final (a, z) = b;
      final l = leftX(g, a), r = rightX(g, z);
      canvas.drawRect(Rect.fromLTRB(l, 0, r, ph), Paint()..color = accent.withOpacity(0.08));
      final edge = Paint()
        ..color = accent
        ..strokeWidth = 1.25;
      canvas.drawLine(Offset(l, 0), Offset(l, ph), edge);
      canvas.drawLine(Offset(r, 0), Offset(r, ph), edge);
      final c = s.candles!;
      final text = '${z - a + 1} bars · ${fmtShort(c.time(a))} → ${fmtShort(DateTime.fromMillisecondsSinceEpoch(_barEnd(c, z), isUtc: true))}';
      final st = ts(11, w: FontWeight.w600);
      final w = text.length * 6.4 + 16;
      tag(canvas, Rect.fromCenter(center: Offset((l + r) / 2, g.bottom + 20), width: w, height: 20), text, accent, C.bg, st);
    }
    for (final sp in spans()) {
      final sel = sp.instance == selected, hov = hoverEdge?.$1 == sp.instance;
      if ((!sel && !hov) || sp.box == null || sp.instance == resizing) continue;
      final y0 = g.y(sp.box!.$2), y1 = g.y(sp.box!.$1);
      final p = Paint()
        ..color = accent.withOpacity(sel ? 1 : 0.6)
        ..strokeWidth = 1.25;
      for (final (x, left) in [(leftX(g, sp.first), true), (rightX(g, sp.last), false)]) {
        canvas.drawLine(Offset(x, y0), Offset(x, y1), p);
        final strong = sel || (hoverEdge?.$2 == left);
        final h = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(x, (y0 + y1) / 2), width: 6, height: 20), const Radius.circular(3));
        canvas.drawRRect(h, Paint()..color = strong ? accent : C.bg);
        canvas.drawRRect(h, Paint()
          ..style = PaintingStyle.stroke
          ..color = accent);
      }
    }
  }
}
