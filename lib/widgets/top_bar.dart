import 'package:flutter/material.dart';

import '../data/candles.dart';
import '../engine/engine_service.dart';
import '../state/app_state.dart';
import '../state/lab_state.dart';
import '../theme.dart';
import 'common.dart';

class TopBar extends StatelessWidget {
  const TopBar({super.key, required this.lab});
  final LabState lab;

  @override
  Widget build(BuildContext context) {
    final s = lab.chart, m = s.run?.manifest;
    return SizedBox(
      height: 48,
      child: Panel(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(children: [
          Segmented<Mode>(
            values: Mode.values,
            selected: s.mode,
            onChanged: s.setMode,
            enabledOf: (_) => s.loaded,
            labelOf: (m) => m == Mode.explore ? 'Explore' : 'Replay',
          ),
          const VDivider(),
          const SizedBox(width: 6),
          Expanded(
            child: m == null
                ? Text(lab.opening ?? (s.candlesPath != null ? 'Data · ${s.candlesPath!.split(RegExp(r'[\\/]')).last}' : 'No run open'),
                    overflow: TextOverflow.ellipsis, style: ts(13, color: C.mute))
                : Row(children: [
                    Flexible(child: Text(m.strategyKey, overflow: TextOverflow.ellipsis, style: ts(13, w: FontWeight.w500))),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text('${m.from ?? 'data start'} → ${m.to ?? 'data end'} · ${m.runId}', overflow: TextOverflow.ellipsis, style: ts(12, color: C.mute)),
                    ),
                    if (m.zeroCost) ...[const SizedBox(width: 10), Text('ZERO-COST RUN', style: capsLabel(color: C.gold))],
                  ]),
          ),
          const SizedBox(width: 8),
          EngineStatusMenu(lab: lab),
          const SizedBox(width: 8),
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
            key: const ValueKey('indicators-button'),
            label: 'Indicators',
            icon: AppIcons.indicators,
            color: s.panelOpen(RightPanel.indicators) ? C.text : C.mute,
            borderColor: s.panelOpen(RightPanel.indicators) ? C.lineHover : C.line,
            onTap: () => s.toggleIndicators(),
          ),
          const SizedBox(width: 8),
          PillButton(
            key: const ValueKey('tester-button'),
            label: 'Tester',
            icon: AppIcons.tester,
            color: s.panelOpen(RightPanel.tester) ? C.text : C.mute,
            borderColor: s.panelOpen(RightPanel.tester) ? C.lineHover : C.line,
            onTap: () => s.toggleRight(),
          ),
          const SizedBox(width: 8),
          PillButton(
            label: 'Results',
            icon: AppIcons.results,
            color: s.bottomOpen ? C.text : C.mute,
            borderColor: s.bottomOpen ? C.lineHover : C.line,
            onTap: () => s.toggleBottom(),
          ),
          const SizedBox(width: 8),
          PillButton(label: 'Focus', icon: AppIcons.focus, onTap: s.toggleFocus, trailing: const Kbd('F')),
        ]),
      ),
    );
  }
}

Color engineColor(EngineStatus st) => switch (st) {
      EngineStatus.ready => C.green,
      EngineStatus.starting => C.gold,
      EngineStatus.error => C.red,
      EngineStatus.stopped => C.mute,
    };

String engineLabel(LabState lab) {
  if (lab.engineBuilding) return 'Building engine…';
  return switch (lab.engine.status) {
    EngineStatus.ready => (lab.freshness?.needsBuild ?? false) ? 'Engine ready · outdated' : 'Engine ready',
    EngineStatus.starting => 'Engine starting…',
    EngineStatus.error => 'Engine error',
    EngineStatus.stopped => 'Engine stopped',
  };
}

/// Status dot + label; the menu shows the message and offers Restart / Build engine.
class EngineStatusMenu extends StatelessWidget {
  const EngineStatusMenu({super.key, required this.lab});
  final LabState lab;

  @override
  Widget build(BuildContext context) {
    final e = lab.engine, f = lab.freshness;
    final col = lab.engineBuilding ? C.gold : engineColor(e.status);
    final outdated = f?.missing == true
        ? 'No engine binary at ${lab.settings.binary}.'
        : (f?.newerSource != null ? 'Engine sources are newer than the binary (${f!.newerSource}).' : null);
    return PopupMenuButton<String>(
      key: const ValueKey('engine-menu'),
      tooltip: '',
      offset: const Offset(0, 40),
      onSelected: (v) {
        if (v == 'restart') lab.restartEngine();
        if (v == 'build') lab.buildEngine();
        if (v == 'settings') lab.chart.toggleLeft(true);
      },
      itemBuilder: (_) => [
        PopupMenuItem<String>(
          enabled: false,
          child: SizedBox(
            width: 340,
            child: Text([e.message ?? engineLabel(lab), ?outdated].join('\n'), style: ts(12, color: C.mute, height: 1.4)),
          ),
        ),
        const PopupMenuDivider(height: 8),
        PopupMenuItem<String>(value: 'restart', height: 34, enabled: !lab.engineBuilding, child: Text('Restart engine', style: ts(13))),
        PopupMenuItem<String>(
          value: 'build',
          height: 34,
          enabled: !lab.engineBuilding,
          child: Text(outdated != null ? 'Build engine (recommended)' : 'Build engine', style: ts(13, color: outdated != null ? C.gold : C.text)),
        ),
        PopupMenuItem<String>(value: 'settings', height: 34, child: Text('Engine paths…', style: ts(13))),
      ],
      child: HoverBox(
        hoverOnly: true,
        builder: (context, h) => Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: h ? C.text.withOpacity(0.05) : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: e.status == EngineStatus.error ? C.red.withOpacity(0.6) : C.line),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 7, height: 7, decoration: BoxDecoration(color: col, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Text(engineLabel(lab), key: const ValueKey('engine-status'), style: ts(12, color: e.ready ? C.mute : C.text)),
          ]),
        ),
      ),
    );
  }
}
