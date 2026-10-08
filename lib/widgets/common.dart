import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme.dart';

class HoverBox extends StatefulWidget {
  const HoverBox({super.key, required this.builder, this.onTap, this.enabled = true, this.hoverOnly = false});
  final Widget Function(BuildContext context, bool hovered) builder;
  final VoidCallback? onTap;
  final bool enabled;

  /// Hover feedback only; taps are handled by a parent (e.g. PopupMenuButton).
  final bool hoverOnly;

  @override
  State<HoverBox> createState() => _HoverBoxState();
}

class _HoverBoxState extends State<HoverBox> {
  bool _h = false;

  @override
  Widget build(BuildContext context) {
    if (widget.hoverOnly) {
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _h = true),
        onExit: (_) => setState(() => _h = false),
        child: widget.builder(context, _h),
      );
    }
    final active = widget.enabled && widget.onTap != null;
    return MouseRegion(
      cursor: active ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _h = true),
      onExit: (_) => setState(() => _h = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: active ? widget.onTap : null,
        child: Opacity(opacity: widget.enabled ? 1 : 0.45, child: widget.builder(context, _h && active)),
      ),
    );
  }
}

enum PillVariant { primary, outline, ghost }

class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.variant = PillVariant.outline,
    this.height = 32,
    this.color,
    this.borderColor,
    this.tint,
    this.fontSize = 13,
    this.enabled = true,
    this.trailing,
    this.leading,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final PillVariant variant;
  final double height, fontSize;
  final Color? color, borderColor, tint;
  final bool enabled;
  final Widget? trailing, leading;

  @override
  Widget build(BuildContext context) => HoverBox(
        onTap: onTap,
        enabled: enabled,
        builder: (context, h) {
          final primary = variant == PillVariant.primary;
          final fg = color ?? (primary ? C.bg : C.text);
          final bg = primary ? (h ? Colors.white : C.text) : (h ? (color ?? C.text).withOpacity(0.08) : (tint ?? Colors.transparent));
          return Container(
            height: height,
            padding: EdgeInsets.symmetric(horizontal: height >= 36 ? 18 : 12),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(999),
              border: variant == PillVariant.outline ? Border.all(color: borderColor ?? C.line) : null,
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (leading != null) ...[leading!, const SizedBox(width: 6)],
              if (icon != null) ...[Icon(icon, size: fontSize + 2, color: fg), const SizedBox(width: 6)],
              Text(label, style: ts(fontSize, color: fg, w: primary ? FontWeight.w600 : FontWeight.w400)),
              if (trailing != null) ...[const SizedBox(width: 6), trailing!],
            ]),
          );
        },
      );
}

class RoundIconButton extends StatelessWidget {
  const RoundIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.size = 28,
    this.iconSize = 16,
    this.tooltip,
    this.filled = false,
    this.radius,
    this.color = C.text,
    this.enabled = true,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final double size, iconSize;
  final double? radius;
  final String? tooltip;
  final bool filled, enabled;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final btn = HoverBox(
      onTap: onTap,
      enabled: enabled,
      builder: (context, h) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? (h ? Colors.white : C.text) : (h ? C.text.withOpacity(0.08) : Colors.transparent),
          borderRadius: BorderRadius.circular(radius ?? size / 2),
        ),
        child: Icon(icon, size: iconSize, color: filled ? C.bg : (h ? C.text : color)),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}

class Segmented<T> extends StatelessWidget {
  const Segmented({
    super.key,
    required this.values,
    required this.selected,
    required this.onChanged,
    this.labelOf,
    this.enabledOf,
    this.height = 28,
    this.fontSize = 13,
    this.padH = 14,
  });

  final bool Function(T)? enabledOf;

  final List<T> values;
  final T selected;
  final ValueChanged<T> onChanged;
  final String Function(T)? labelOf;
  final double height, fontSize, padH;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: C.bg, borderRadius: BorderRadius.circular(999), border: Border.all(color: C.line)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final v in values)
              HoverBox(
                enabled: enabledOf?.call(v) ?? true,
                onTap: () => onChanged(v),
                builder: (context, h) {
                  final on = v == selected;
                  return Container(
                    height: height,
                    padding: EdgeInsets.symmetric(horizontal: padH),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: on ? C.line : Colors.transparent, borderRadius: BorderRadius.circular(999)),
                    child: Text(labelOf?.call(v) ?? '$v', style: ts(fontSize, color: on || h ? C.text : C.mute, w: FontWeight.w500)),
                  );
                },
              ),
          ],
        ),
      );
}

class PillSwitch extends StatelessWidget {
  const PillSwitch({super.key, required this.value, this.onChanged, this.enabled = true, this.width = 30, this.height = 18});
  final bool value, enabled;
  final ValueChanged<bool>? onChanged;
  final double width, height;

  @override
  Widget build(BuildContext context) => HoverBox(
        enabled: enabled,
        onTap: onChanged == null ? null : () => onChanged!(!value),
        builder: (context, _) => AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: width,
          height: height,
          padding: const EdgeInsets.all(2),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          decoration: BoxDecoration(color: value ? C.text : C.line, borderRadius: BorderRadius.circular(999)),
          child: Container(
            width: height - 4,
            height: height - 4,
            decoration: BoxDecoration(color: value ? C.bg : C.mute, shape: BoxShape.circle),
          ),
        ),
      );
}

class VDivider extends StatelessWidget {
  const VDivider({super.key, this.height = 20, this.margin = 4});
  final double height, margin;
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: height, margin: EdgeInsets.symmetric(horizontal: margin), color: C.line);
}

class Kbd extends StatelessWidget {
  const Kbd(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(border: Border.all(color: C.line), borderRadius: BorderRadius.circular(6)),
        child: Text(text, style: ts(11, color: C.mute)),
      );
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(), style: capsLabel());
}

class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding = EdgeInsets.zero, this.radius = 16, this.color = C.panel, this.shadow});
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final Color color;
  final List<BoxShadow>? shadow;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: C.line),
          boxShadow: shadow,
        ),
        child: child,
      );
}

/// Translucent floating surface for overlays on the chart.
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.radius = 999,
    this.padding = const EdgeInsets.all(4),
    this.opacity = 0.85,
    this.borderColor = C.line,
    this.shadow = false,
  });
  final Widget child;
  final double radius, opacity;
  final EdgeInsets padding;
  final Color borderColor;
  final bool shadow;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          boxShadow: shadow ? const [BoxShadow(color: Color(0x73000000), blurRadius: 40, offset: Offset(0, 12))] : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              padding: padding,
              decoration: BoxDecoration(
                color: C.panel.withOpacity(opacity),
                borderRadius: BorderRadius.circular(radius),
                border: Border.all(color: borderColor),
              ),
              child: child,
            ),
          ),
        ),
      );
}

/// Large light-weight number with dimmed decimals: 58[.3%]
class BigNumber extends StatelessWidget {
  const BigNumber(this.whole, this.rest, {super.key, this.size = 28, this.color = C.text, this.restColor = C.mute});
  final String whole, rest;
  final double size;
  final Color color, restColor;

  @override
  Widget build(BuildContext context) {
    final st = ts(size, color: color, w: FontWeight.w300, ls: -0.02 * size, height: 1.1);
    return RichText(
      text: TextSpan(children: [
        TextSpan(text: whole, style: st),
        TextSpan(text: rest, style: st.copyWith(color: restColor)),
      ]),
    );
  }
}
