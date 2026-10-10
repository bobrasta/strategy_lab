import 'package:flutter/material.dart';

import '../theme.dart';
import 'common.dart';

/// A one-line pill text field bound to a value the app owns. It follows outside changes while
/// it isn't being edited, and reports every edit.
class PillField extends StatefulWidget {
  const PillField({
    super.key,
    required this.value,
    required this.onChanged,
    this.hint = '',
    this.width,
    this.error = false,
    this.mono = false,
    this.fieldKey,
  });
  final String value, hint;
  final ValueChanged<String> onChanged;
  final double? width;
  final bool error, mono;
  final Key? fieldKey;

  @override
  State<PillField> createState() => _PillFieldState();
}

class _PillFieldState extends State<PillField> {
  late final TextEditingController _c = TextEditingController(text: widget.value);
  final FocusNode _f = FocusNode();

  @override
  void didUpdateWidget(PillField old) {
    super.didUpdateWidget(old);
    if (!_f.hasFocus && _c.text != widget.value) _c.text = widget.value;
  }

  @override
  void dispose() {
    _c.dispose();
    _f.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
        width: widget.width,
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: C.bg,
          border: Border.all(color: widget.error ? C.red.withOpacity(0.7) : C.line),
          borderRadius: BorderRadius.circular(999),
        ),
        child: TextField(
          key: widget.fieldKey,
          controller: _c,
          focusNode: _f,
          onChanged: widget.onChanged,
          style: ts(12),
          decoration: InputDecoration.collapsed(hintText: widget.hint, hintStyle: ts(12, color: C.mute)),
        ),
      );
}

/// Label on the left, control on the right, an optional muted line below.
class FormRow extends StatelessWidget {
  const FormRow({super.key, required this.label, required this.child, this.sub, this.subColor = C.mute, this.labelWidth = 110});
  final String label;
  final String? sub;
  final Color subColor;
  final Widget child;
  final double labelWidth;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            SizedBox(width: labelWidth, child: Text(label, overflow: TextOverflow.ellipsis, style: ts(12, color: C.mute))),
            Expanded(child: Align(alignment: Alignment.centerLeft, child: child)),
          ]),
          if (sub != null && sub!.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(left: labelWidth, top: 3),
              child: Text(sub!, style: ts(11, color: subColor, height: 1.35)),
            ),
        ]),
      );
}

/// A small popup picker in the pill style.
class PillMenu<T> extends StatelessWidget {
  const PillMenu({super.key, required this.values, required this.selected, required this.onSelected, required this.labelOf, this.enabled = true, this.leading});
  final List<T> values;
  final T selected;
  final ValueChanged<T> onSelected;
  final String Function(T) labelOf;
  final bool enabled;
  final Widget Function(T)? leading;

  @override
  Widget build(BuildContext context) => PopupMenuButton<T>(
        tooltip: '',
        enabled: enabled,
        offset: const Offset(0, 34),
        onSelected: onSelected,
        itemBuilder: (_) => [
          for (final v in values)
            PopupMenuItem<T>(
              value: v,
              height: 34,
              child: Row(children: [
                SizedBox(width: 20, child: v == selected ? const Icon(AppIcons.check, size: 14, color: C.gold) : null),
                if (leading != null) ...[leading!(v), const SizedBox(width: 8)],
                Text(labelOf(v), style: ts(13, color: v == selected ? C.text : C.mute)),
              ]),
            ),
        ],
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: HoverBox(
            hoverOnly: true,
            builder: (context, h) => Container(
              height: 30,
              padding: const EdgeInsets.only(left: 12, right: 8),
              decoration: BoxDecoration(
                color: h ? C.text.withOpacity(0.05) : C.bg,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: C.line),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (leading != null) ...[leading!(selected), const SizedBox(width: 8)],
                Flexible(child: Text(labelOf(selected), overflow: TextOverflow.ellipsis, style: ts(12))),
                const SizedBox(width: 4),
                const Icon(AppIcons.down, size: 14, color: C.mute),
              ]),
            ),
          ),
        ),
      );
}
