import 'package:flutter/material.dart';

import '../data/candles.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'common.dart';

class TopBar extends StatelessWidget {
  const TopBar({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final mismatch = s.eventsTf != null && s.drill == null && s.timeframe != s.eventsTf;
    final canReload = s.candlesPath != null || s.eventsPath != null;
    return SizedBox(
      height: 48,
      child: Panel(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(children: [
          Segmented<Mode>(
            values: Mode.values,
            selected: s.mode,
            onChanged: s.setMode,
            labelOf: (m) => m == Mode.explore ? 'Explore' : 'Replay',
          ),
          const VDivider(),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final k in kFilterOptions.keys)
                    if (!kConditionFilters.contains(k)) ...[_FilterMenu(state: s, name: k), const SizedBox(width: 6)],
                  _ConditionFilters(state: s),
                  const SizedBox(width: 6),
                  _StarredChip(on: s.starredOnly, onTap: s.toggleStarredOnly),
                  const SizedBox(width: 6),
                  _PresetsMenu(state: s),
                ]),
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (s.eventsTf != null) ...[
            Tooltip(
              message: mismatch ? 'Zones are drawn only on ${s.eventsTf}' : 'Zones come from fvg_events.csv',
              child: Text(mismatch ? 'Events are ${s.eventsTf} · zones hidden' : 'Events are ${s.eventsTf}',
                  style: ts(11, color: mismatch ? C.text : C.mute)),
            ),
            const SizedBox(width: 8),
          ],
          Segmented<String>(
            values: kTimeframes,
            selected: s.timeframe,
            onChanged: s.setTimeframe,
            enabledOf: (tf) => tf == s.timeframe || s.tfAvailable(tf),
            height: 26,
            fontSize: 12,
            padH: 10,
          ),
          const SizedBox(width: 8),
          PillButton(
            label: 'Stats',
            icon: AppIcons.stats,
            color: s.rightOpen ? C.text : C.mute,
            borderColor: s.rightOpen ? C.lineHover : C.line,
            onTap: s.toggleRight,
          ),
          const SizedBox(width: 8),
          PillButton(label: 'Focus', icon: AppIcons.focus, onTap: s.toggleFocus, trailing: const Kbd('F')),
          const SizedBox(width: 8),
          Tooltip(
            message: 'Re-read the candle and events files after re-running the Python study',
            child: PillButton(
              label: s.busy ?? 'Reload study',
              icon: s.busy == null ? AppIcons.replayEvent : null,
              leading: s.busy == null
                  ? null
                  : const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, color: C.bg)),
              variant: PillVariant.primary,
              enabled: s.busy != null || canReload,
              onTap: s.busy == null && canReload ? s.reload : null,
            ),
          ),
        ]),
      ),
    );
  }
}

class _FilterMenu extends StatelessWidget {
  const _FilterMenu({required this.state, required this.name});
  final AppState state;
  final String name;

  @override
  Widget build(BuildContext context) {
    final opts = kFilterOptions[name]!, sel = state.filters[name]!, available = state.filterAvailable(name);
    return PopupMenuButton<int>(
      tooltip: available ? '' : 'No ${name.toLowerCase()} column in fvg_events.csv',
      enabled: available,
      offset: const Offset(0, 38),
      onSelected: (i) => state.setFilter(name, i),
      itemBuilder: (_) => [
        for (var i = 0; i < opts.length; i++)
          PopupMenuItem<int>(
            value: i,
            height: 34,
            child: Row(children: [
              SizedBox(width: 20, child: i == sel ? const Icon(AppIcons.check, size: 14, color: C.gold) : null),
              Text(opts[i], style: ts(13, color: i == sel ? C.text : C.mute)),
            ]),
          ),
      ],
      child: Opacity(
        opacity: available ? 1 : 0.45,
        child: HoverBox(
        hoverOnly: true,
        builder: (context, h) => Container(
          height: 32,
          padding: const EdgeInsets.only(left: 14, right: 10),
          decoration: BoxDecoration(
            color: h ? C.text.withOpacity(0.05) : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: C.line),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(name, style: ts(13, color: C.mute)),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 170),
              child: Text(opts[sel], overflow: TextOverflow.ellipsis, style: ts(13, color: sel != 0 ? C.text : C.mute)),
            ),
            const SizedBox(width: 4),
            const Icon(AppIcons.down, size: 14, color: C.mute),
          ]),
        ),
      ),
      ),
    );
  }
}

/// "Filters" button with a count badge; opens a popover with the conditional-study filters.
class _ConditionFilters extends StatefulWidget {
  const _ConditionFilters({required this.state});
  final AppState state;

  @override
  State<_ConditionFilters> createState() => _ConditionFiltersState();
}

class _ConditionFiltersState extends State<_ConditionFilters> {
  final _portal = OverlayPortalController();
  final _link = LayerLink();

  @override
  Widget build(BuildContext context) {
    final s = widget.state, n = s.activeConditionFilters;
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (_) => Stack(children: [
          Positioned.fill(child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: _portal.hide)),
          CompositedTransformFollower(
            link: _link,
            targetAnchor: Alignment.bottomLeft,
            offset: const Offset(0, 6),
            child: Align(
              alignment: Alignment.topLeft,
              child: Material(type: MaterialType.transparency, child: ListenableBuilder(listenable: s, builder: (_, _) => _FiltersPanel(state: s))),
            ),
          ),
        ]),
        child: HoverBox(
          onTap: _portal.toggle,
          builder: (context, h) => Container(
            key: const ValueKey('filters-button'),
            height: 32,
            padding: const EdgeInsets.only(left: 12, right: 10),
            decoration: BoxDecoration(
              color: h ? C.text.withOpacity(0.05) : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: n > 0 ? C.lineHover : C.line),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(AppIcons.study, size: 14, color: n > 0 ? C.text : C.mute),
              const SizedBox(width: 6),
              Text('Filters', style: ts(13, color: n > 0 ? C.text : C.mute)),
              if (n > 0) ...[
                const SizedBox(width: 6),
                Container(
                  height: 18,
                  constraints: const BoxConstraints(minWidth: 18),
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: C.gold.withOpacity(0.15), borderRadius: BorderRadius.circular(999)),
                  child: Text('$n', style: ts(11, color: C.gold, w: FontWeight.w600)),
                ),
              ],
              const SizedBox(width: 4),
              const Icon(AppIcons.down, size: 14, color: C.mute),
            ]),
          ),
        ),
      ),
    );
  }
}

class _FiltersPanel extends StatelessWidget {
  const _FiltersPanel({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final s = state;
    return Panel(
      radius: 12,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      shadow: const [BoxShadow(color: Color(0x73000000), blurRadius: 40, offset: Offset(0, 12))],
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          Text('Conditions', style: ts(13, w: FontWeight.w500)),
          const SizedBox(width: 12),
          Text('Same filters apply to fake and control zones', style: ts(11, color: C.mute)),
        ]),
        const SizedBox(height: 10),
        for (final k in kConditionFilters) _row(s, k),
        const SizedBox(height: 6),
        PillButton(label: 'Reset conditions', height: 28, fontSize: 12, enabled: s.activeConditionFilters > 0, onTap: s.clearConditionFilters),
      ]),
    );
  }

  Widget _row(AppState s, String k) {
    final opts = kFilterOptions[k]!, available = s.filterAvailable(k);
    final row = Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(width: 120, child: Text(k, style: ts(12, color: C.mute))),
        Segmented<int>(
          values: [for (var i = 0; i < opts.length; i++) i],
          selected: s.filters[k]!,
          onChanged: (i) => s.setFilter(k, i),
          labelOf: (i) => opts[i],
          enabledOf: (_) => available,
          height: 24,
          fontSize: 12,
          padH: 10,
        ),
      ]),
    );
    return available ? row : Tooltip(message: 'No ${k.toLowerCase()} column in the events file', child: row);
  }
}

class _PresetsMenu extends StatelessWidget {
  const _PresetsMenu({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
        tooltip: '',
        offset: const Offset(0, 38),
        onSelected: (v) => v == '__clear' ? state.clearFilters() : state.applyFilterPreset(v),
        itemBuilder: (_) => [
          for (final name in kFilterPresets.keys)
            PopupMenuItem<String>(value: name, height: 34, child: Text(name, style: ts(13))),
          const PopupMenuDivider(height: 8),
          PopupMenuItem<String>(value: '__clear', height: 34, enabled: state.anyFilter, child: Text('Clear all filters', style: ts(13, color: C.mute))),
        ],
        child: HoverBox(
          hoverOnly: true,
          builder: (context, h) => Container(
            height: 32,
            padding: const EdgeInsets.only(left: 12, right: 10),
            decoration: BoxDecoration(
              color: h ? C.text.withOpacity(0.05) : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: C.line),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.bookmarks_outlined, size: 14, color: C.mute),
              const SizedBox(width: 6),
              Text('Presets', style: ts(13, color: C.mute)),
              const SizedBox(width: 4),
              const Icon(AppIcons.down, size: 14, color: C.mute),
            ]),
          ),
        ),
      );
}

class _StarredChip extends StatelessWidget {
  const _StarredChip({required this.on, required this.onTap});
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => HoverBox(
        onTap: onTap,
        builder: (context, h) => Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: on ? C.line : (h ? C.text.withOpacity(0.05) : Colors.transparent),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: on ? C.lineHover : C.line),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(on ? AppIcons.star : AppIcons.starOutline, size: 15, color: on ? C.gold : C.mute),
            const SizedBox(width: 6),
            Text('Starred', style: ts(13, color: on ? C.text : C.mute)),
          ]),
        ),
      );
}
