import 'package:flutter/material.dart';

import '../chart/fvg_layer.dart';
import '../data/events.dart';
import '../theme.dart';

Widget _pill(String text, Color fg) => Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: fg.withOpacity(fg == C.text ? 0.08 : 0.13), borderRadius: BorderRadius.circular(999)),
      child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(11, color: fg, w: FontWeight.w500)),
    );

/// Outcome pill: Bounce / Break / Timeout, or neutral "Open" while hidden in replay.
Widget outcomePill(EvOutcome? o) => o == null ? _pill('Open', C.text) : _pill(outcomeLabel(o), FvgLayer.outcomeColor(o));

/// Scenario pill, coloured by the outcome family it belongs to.
Widget scenarioPill(String? code) {
  if (code == null) return _pill('—', C.text);
  final o = scenarioOutcome(code);
  return _pill(scenarioLabel(code), o == null ? C.text : FvgLayer.outcomeColor(o));
}
