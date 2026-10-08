import 'package:flutter/painting.dart';

import '../data/candles.dart';
import '../state/app_state.dart';
import 'chart_geometry.dart';
import 'fvg_layer.dart';

class LayerContext {
  const LayerContext({required this.state, required this.candles, required this.cursor, required this.pulse});
  final AppState state;
  final Candles candles;

  /// Last knowable bar. Layers must not read data beyond it.
  final int cursor;

  /// 0..1 intensity of the one-time resolution pulse.
  final double pulse;

  bool get isReplay => state.isReplay && !state.selectMode;
}

/// A modular chart overlay. Every layer gets the same [LayerContext.cursor]
/// so replay hides the future for all of them in the same way.
abstract class ChartLayer {
  const ChartLayer();
  String get id;
  String get label;
  String get description;
  bool get available => true;

  /// Layers that dock to the right edge of the plot (volume profile) reserve width here.
  double get dockedRightWidth => 0;

  void paintBelow(Canvas canvas, ChartGeometry g, LayerContext ctx) {}
  void paintAbove(Canvas canvas, ChartGeometry g, LayerContext ctx) {}
}

class SwingPointsLayer extends ChartLayer {
  const SwingPointsLayer();
  @override
  String get id => 'swings';
  @override
  String get label => 'Swing points';
  @override
  String get description => 'Coming soon';
  @override
  bool get available => false;
}

/// Reserved slot: a horizontal volume histogram docked to the right edge of the plot.
class VolumeProfileLayer extends ChartLayer {
  const VolumeProfileLayer();
  @override
  String get id => 'volume';
  @override
  String get label => 'Volume profile';
  @override
  String get description => 'Coming soon';
  @override
  bool get available => false;
  @override
  double get dockedRightWidth => 120;
}

const List<ChartLayer> chartLayers = [FvgLayer(), SwingPointsLayer(), VolumeProfileLayer()];
