import 'package:flutter/painting.dart';

import '../data/candles.dart';
import '../state/app_state.dart';
import 'chart_geometry.dart';
import 'drawings_layer.dart';
import 'fvg_layer.dart';
import 'trades_layer.dart';

class LayerContext {
  const LayerContext({required this.state, required this.candles, required this.cursor, required this.nowMs});
  final AppState state;
  final Candles candles;

  /// Last knowable bar. Layers must not read data beyond it.
  final int cursor;

  /// Last knowable instant (the cursor bar's last tick). Nothing stamped later may be drawn.
  final int nowMs;

  bool get isReplay => state.isReplay && !state.selectMode;

  /// Bar index of [ms] on the chart's timeframe.
  int bar(int ms) => candles.barAt(ms);

  /// Visible time span of the view (bar opens), for culling.
  (int, int) viewSpan(ChartGeometry g) {
    final a = g.viewStart.clamp(0, candles.length - 1).toInt();
    final b = (g.viewStart + g.slots).clamp(0, candles.length - 1).toInt();
    return (candles.t[a], candles.endMs(b));
  }
}

/// A modular chart overlay. Every layer gets the same [LayerContext.cursor] / [LayerContext.nowMs]
/// so replay hides the future for all of them in the same way.
abstract class ChartLayer {
  const ChartLayer();
  String get id;
  String get label;
  String get description;
  bool available(AppState s) => true;

  /// Painted now: available and switched on (indicator layers carry their own visibility).
  bool isOn(AppState s) => available(s) && s.layersOn.contains(id);

  void paintBelow(Canvas canvas, ChartGeometry g, LayerContext ctx) {}
  void paintAbove(Canvas canvas, ChartGeometry g, LayerContext ctx) {}
}

const List<ChartLayer> chartLayers = [TradesLayer(), DrawingsLayer(), FvgLayer()];

/// The fixed layers, then one per attached indicator (in the Indicators order, later on top).
List<ChartLayer> layersOf(AppState s) => [...chartLayers, ...s.indicatorLayers, ?s.practiceLayer];
