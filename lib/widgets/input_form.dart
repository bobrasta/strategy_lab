import 'package:flutter/material.dart';

import '../state/lab_state.dart';
import '../theme.dart';
import 'common.dart';
import 'fields.dart';

/// One input of a strategy or indicator schema (`hummer inputs`): a text field, switch or menu by
/// type, with its description, range and default. Used by the Tester and the Indicators form.
class InputRow extends StatelessWidget {
  const InputRow({super.key, required this.spec, required this.value, required this.onChanged, this.labelWidth = 120});
  final InputSpec spec;
  final String value;
  final ValueChanged<String> onChanged;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    final v = value, err = spec.check(v), isDefault = v == spec.def;
    final Widget control = switch (spec.type) {
      'bool' => PillSwitch(value: v == 'true', onChanged: (x) => onChanged('$x')),
      'timeframe' => PillMenu<String>(values: kStrategyTimeframes, selected: kStrategyTimeframes.contains(v) ? v : spec.def, onSelected: onChanged, labelOf: (x) => x),
      'choice' => PillMenu<String>(values: spec.choices, selected: spec.choices.contains(v) ? v : spec.def, onSelected: onChanged, labelOf: (x) => x),
      _ => PillField(value: v, hint: spec.def, width: 140, error: err != null, onChanged: (x) => onChanged(x.trim().isEmpty ? spec.def : x.trim())),
    };
    final range = spec.min != null || spec.max != null ? ' · ${spec.min == null ? '' : _n(spec.min!)}–${spec.max == null ? '' : _n(spec.max!)}' : '';
    return FormRow(
      label: spec.name,
      labelWidth: labelWidth,
      sub: err ?? '${spec.description}$range${isDefault ? '' : ' · default ${spec.def}'}',
      subColor: err != null ? C.red : (isDefault ? C.mute : C.gold),
      child: control,
    );
  }

  static String _n(double x) => x == x.truncateToDouble() ? x.toInt().toString() : '$x';
}
