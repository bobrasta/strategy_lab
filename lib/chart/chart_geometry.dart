import 'dart:math';
import 'dart:ui';

import '../data/candles.dart';
import '../state/app_state.dart';

class ChartGeometry {
  ChartGeometry({
    required this.size,
    required this.viewStart,
    required this.zoom,
    required this.lo,
    required this.hi,
    required this.top,
    required this.bottom,
    this.dockRight = 0,
  });

  static const double axisRight = 72, axisBottom = 28;

  /// Empty slots right of the last bar: room for labels and the replay future.
  static const int rightPadBars = 16;

  final Size size;
  final int viewStart, zoom;
  final double lo, hi, top, bottom;

  /// Width reserved by right-docked layers (e.g. a volume profile).
  final double dockRight;

  double get axisX => size.width - axisRight;
  double get plotW => axisX - dockRight;
  double get plotH => size.height - axisBottom;
  int get slots => zoom + rightPadBars;
  double get xs => plotW / slots;

  double x(int i) => (i - viewStart + 0.5) * xs;
  double y(double p) => top + (hi - p) / (hi - lo) * (bottom - top);
  double price(double py) => hi - (py - top) / (bottom - top) * (hi - lo);
  int barAt(double px) => (px / xs + viewStart).floor();

  /// Autoscale reads only bars at or before [cursor] — no lookahead via scaling.
  factory ChartGeometry.compute(Size size, AppState s, Candles c, int cursor, double dockRight) {
    final kStart = max(0, s.viewStart - 1);
    final kEnd = min(min(cursor, c.length - 1), s.viewStart + s.zoom + rightPadBars);
    var lo = double.infinity, hi = -double.infinity;
    for (var i = kStart; i <= kEnd; i++) {
      if (c.l[i] < lo) lo = c.l[i];
      if (c.h[i] > hi) hi = c.h[i];
    }
    if (!lo.isFinite || hi <= lo) {
      lo = lo.isFinite ? lo - 1 : 0;
      hi = lo + 2;
    }
    final pad = (hi - lo) * 0.08;
    var vlo = lo - pad, vhi = hi + pad;
    if (s.priceManual) {
      // User scale/shift applied to the autoscaled range, so it still never reads past the cursor.
      final range = vhi - vlo, mid = (vlo + vhi) / 2 + s.priceShift * range, half = range / 2 / s.priceZoom;
      vlo = mid - half;
      vhi = mid + half;
    }
    final plotH = size.height - axisBottom;
    return ChartGeometry(
      size: size,
      viewStart: s.viewStart,
      zoom: s.zoom,
      lo: vlo,
      hi: vhi,
      top: 72,
      bottom: plotH - (s.isReplay ? 104 : 40),
      dockRight: dockRight,
    );
  }
}
