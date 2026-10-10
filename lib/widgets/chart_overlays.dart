import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../state/lab_state.dart';
import '../theme.dart';
import '../util/format.dart';
import 'common.dart';

/// Top-left: symbol, bar time, OHLC of the hovered (or last knowable) bar.
class OhlcReadout extends StatelessWidget {
  const OhlcReadout({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<HoverInfo?>(
        valueListenable: state.hover,
        builder: (context, hv, _) {
          final s = state, c = s.candles!, cur = s.visibleCursor;
          final hb = (hv?.bar ?? cur).clamp(0, cur).toInt();
          final pb = hb > 0 ? hb - 1 : 0, chg = c.c[hb] - c.c[pb];
          Widget v(String k, double p) => Text.rich(TextSpan(children: [
                TextSpan(text: '$k ', style: ts(12, color: C.mute)),
                TextSpan(text: fmtPrice(p), style: ts(12)),
              ]));
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('${s.run?.manifest.profile['symbol'] ?? 'XAUUSD'}', style: ts(13, w: FontWeight.w600, ls: 0.3)),
              const SizedBox(width: 10),
              Text('${s.timeframe} · ${fmtShort(c.time(hb))} UTC', style: ts(12, color: C.mute)),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              v('O', c.o[hb]), const SizedBox(width: 14),
              v('H', c.h[hb]), const SizedBox(width: 14),
              v('L', c.l[hb]), const SizedBox(width: 14),
              v('C', c.c[hb]), const SizedBox(width: 14),
              Text('${fmtSigned(chg)} (${fmtSigned(c.c[pb] == 0 ? 0 : chg / c.c[pb] * 100)}%)', style: ts(12, color: chg >= 0 ? C.green : C.red)),
            ]),
          ]);
        },
      );
}

class ChartToolbar extends StatelessWidget {
  const ChartToolbar({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final s = state;
    Widget toggle(String id, String label) {
      final on = s.layersOn.contains(id);
      return HoverBox(
        onTap: () => s.toggleLayer(id),
        builder: (context, h) => Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: on ? C.line : (h ? C.text.withOpacity(0.06) : Colors.transparent), borderRadius: BorderRadius.circular(999)),
          child: Text(label, style: ts(12, color: on ? C.text : C.mute)),
        ),
      );
    }

    return Glass(
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        RoundIconButton(icon: AppIcons.zoomIn, tooltip: 'Zoom in', onTap: () => s.zoomBy(0.8)),
        RoundIconButton(icon: AppIcons.zoomOut, tooltip: 'Zoom out', onTap: () => s.zoomBy(1.25)),
        RoundIconButton(icon: AppIcons.fit, tooltip: 'Fit', onTap: s.fit),
        const VDivider(height: 16),
        if (s.run != null) ...[toggle('trades', 'Trades'), toggle('drawings', 'Drawings')],
        if (s.events.isNotEmpty) toggle('fvg', 'FVG zones'),
      ]),
    );
  }
}

class ReplayTools extends StatelessWidget {
  const ReplayTools({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final s = state;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Glass(
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          PillButton(
            label: 'Select bar',
            icon: AppIcons.selectBar,
            height: 28,
            fontSize: 12,
            color: s.selectMode ? C.gold : C.text,
            borderColor: s.selectMode ? C.gold : Colors.transparent,
            onTap: s.toggleSelect,
          ),
          PillButton(label: 'Jump to date', icon: AppIcons.calendar, height: 28, fontSize: 12, variant: PillVariant.ghost, onTap: s.toggleJump),
          Tooltip(
            message: 'Starts 50 bars before the selected trade opens',
            child: PillButton(
              label: 'Replay selected trade',
              icon: AppIcons.replayEvent,
              height: 28,
              fontSize: 12,
              variant: PillVariant.ghost,
              enabled: s.selectedTrade != null,
              onTap: () => s.replayTrade(s.selectedTrade!),
            ),
          ),
        ]),
      ),
      if (s.selectMode) ...[
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: C.gold.withOpacity(0.12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: C.gold.withOpacity(0.4)),
          ),
          child: Text('Click a candle to cut the chart there · Esc to cancel', style: ts(12, color: C.gold)),
        ),
      ],
      if (s.jumpOpen) ...[const SizedBox(height: 8), _JumpPopover(state: s)],
    ]);
  }
}

class _JumpPopover extends StatefulWidget {
  const _JumpPopover({required this.state});
  final AppState state;
  @override
  State<_JumpPopover> createState() => _JumpPopoverState();
}

class _JumpPopoverState extends State<_JumpPopover> {
  late final TextEditingController _c = TextEditingController(text: fmtFull(widget.state.timeOf(widget.state.cursor)));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _go() {
    final t = DateTime.tryParse('${_c.text.trim().replaceFirst(' ', 'T')}Z');
    if (t != null) widget.state.jumpTo(t);
  }

  @override
  Widget build(BuildContext context) => Panel(
        radius: 999,
        padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('UTC', style: ts(12, color: C.mute)),
          const SizedBox(width: 8),
          SizedBox(
            width: 140,
            child: TextField(
              controller: _c,
              autofocus: true,
              onSubmitted: (_) => _go(),
              style: ts(13),
              decoration: InputDecoration.collapsed(hintText: 'YYYY-MM-DD HH:MM', hintStyle: ts(13, color: C.mute)),
            ),
          ),
          PillButton(label: 'Go', variant: PillVariant.primary, height: 28, fontSize: 12, onTap: _go),
        ]),
      );
}

class ReplayDock extends StatelessWidget {
  const ReplayDock({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final s = state, cur = s.visibleCursor;
    final status = s.playing ? 'playing' : 'paused';
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Glass(
        opacity: 0.92,
        shadow: true,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: SizedBox(
          height: 54,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            RoundIconButton(icon: AppIcons.toStart, size: 36, iconSize: 18, tooltip: 'Back to start', onTap: s.toStart),
            RoundIconButton(icon: AppIcons.stepBack, size: 36, iconSize: 20, tooltip: 'Step back (←)', onTap: () => s.step(-1)),
            const SizedBox(width: 2),
            RoundIconButton(
              icon: s.playing ? AppIcons.pause : AppIcons.play,
              size: 42,
              iconSize: 22,
              filled: true,
              tooltip: 'Play / pause (Space)',
              onTap: s.togglePlay,
            ),
            const SizedBox(width: 2),
            RoundIconButton(icon: AppIcons.stepFwd, size: 36, iconSize: 20, tooltip: 'Step forward (→) · Shift+→ next trade event', onTap: () => s.step(1)),
            const SizedBox(width: 4),
            PillButton(label: 'Next trade', icon: AppIcons.nextTrade, height: 32, fontSize: 12, variant: PillVariant.ghost, trailing: const Kbd('N'), onTap: s.nextTrade, enabled: s.run != null),
            const VDivider(height: 24, margin: 8),
            Segmented<int>(values: kSpeeds, selected: s.speed, onChanged: s.setSpeed, labelOf: (v) => '$v×', height: 26, fontSize: 12, padH: 8),
            const SizedBox(width: 6),
            Text('bars/s', style: ts(11, color: C.mute)),
            const VDivider(height: 24, margin: 8),
            SizedBox(
              width: 176,
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.selectMode ? 'Choose a start bar' : fmtDock(s.timeOf(cur)), style: ts(13)),
                const SizedBox(height: 1),
                Text(s.selectMode ? 'Future hidden after the cut' : '${fmtInt(cur - s.replayStart)} bars · $status', style: ts(11, color: C.mute)),
              ]),
            ),
            PillButton(label: 'Exit replay', icon: AppIcons.close, height: 36, fontSize: 12, onTap: s.exitReplay),
          ]),
        ),
      ),
    );
  }
}

/// Error / notice banner in the app's voice.
class MessageBanner extends StatelessWidget {
  const MessageBanner({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final err = state.error;
    final msg = err ?? state.notice;
    if (msg == null) return const SizedBox.shrink();
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: Glass(
        radius: 14,
        opacity: 0.95,
        shadow: true,
        borderColor: err != null ? C.red.withOpacity(0.6) : C.line,
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(err != null ? AppIcons.warn : AppIcons.info, size: 16, color: err != null ? C.red : C.mute),
          ),
          const SizedBox(width: 10),
          Flexible(child: Text(msg, style: ts(13, height: 1.4))),
          const SizedBox(width: 6),
          RoundIconButton(icon: AppIcons.close, size: 24, iconSize: 14, color: C.mute, onTap: state.clearMessage),
        ]),
      ),
    );
  }
}

class _DotGrid extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final p = Paint()..color = C.line;
    for (double x = 14; x < s.width; x += 28) {
      for (double y = 14; y < s.height; y += 28) {
        c.drawCircle(Offset(x, y), 1, p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// Position, floating P&L, equity, balance and margin at the cursor: the exact equity.csv row
/// stamped at or before the cursor's last tick, and the trade open at that moment.
class RunReadout extends StatelessWidget {
  const RunReadout({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final s = state, run = s.run;
    if (run == null) return const SizedBox.shrink();
    final now = s.nowMs, row = run.equityAt(now), pos = run.positionAt(now);
    Widget stat(String v, String l, {Color color = C.text, Key? key}) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(v, key: key, style: ts(16, w: FontWeight.w300, color: color)),
          const SizedBox(height: 2),
          Text(l, style: ts(11, color: C.mute)),
        ]);
    final profit = row?.profit;
    return Glass(
      radius: 12,
      opacity: 0.82,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: IntrinsicHeight(
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Center(child: Text(s.isReplay && !s.selectMode ? 'REPLAY' : 'END OF RUN', style: capsLabel(color: s.isReplay ? C.gold : C.mute))),
          const SizedBox(width: 18),
          stat(
            pos == null ? 'Flat' : '${pos.isBuy ? 'Buy' : 'Sell'} ${pos.volume} @ ${pos.openPrice.toStringAsFixed(3)}',
            pos == null ? 'Position' : 'Position #${pos.ticket}${pos.slInitial > 0 ? ' · SL ${pos.slInitial.toStringAsFixed(3)}' : ''}${pos.tpInitial > 0 ? ' · TP ${pos.tpInitial.toStringAsFixed(3)}' : ''}',
            key: const ValueKey('readout-position'),
          ),
          const SizedBox(width: 18),
          stat(fmtMoneySigned(profit), 'Floating P&L', color: profit == null || profit == 0 ? C.text : (profit > 0 ? C.green : C.red)),
          const SizedBox(width: 18),
          stat(fmtMoney(row?.equity), 'Equity', key: const ValueKey('readout-equity')),
          const SizedBox(width: 18),
          stat(fmtMoney(row?.balance), 'Balance'),
          const SizedBox(width: 18),
          stat(fmtMoney(row?.margin), 'Margin'),
          if (row != null) ...[
            const SizedBox(width: 18),
            Container(width: 1, color: C.line),
            const SizedBox(width: 12),
            Center(child: Text('equity.csv\n${fmtShort(DateTime.fromMillisecondsSinceEpoch(row.ms, isUtc: true))}', style: ts(10.5, color: C.mute, height: 1.3))),
          ],
        ]),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.lab});
  final LabState lab;

  @override
  Widget build(BuildContext context) {
    final s = lab.chart;
    return CustomPaint(
      painter: _DotGrid(),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
          decoration: BoxDecoration(color: C.bg, borderRadius: BorderRadius.circular(16)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: C.line)),
              child: lab.opening != null
                  ? const Padding(padding: EdgeInsets.all(14), child: CircularProgressIndicator(strokeWidth: 1.5, color: C.mute))
                  : const Icon(AppIcons.tester, size: 20, color: C.mute),
            ),
            const SizedBox(height: 20),
            Text(lab.opening ?? 'Start a backtest in the Tester, or open a past run from History.', style: ts(15)),
            const SizedBox(height: 20),
            Row(mainAxisSize: MainAxisSize.min, children: [
              PillButton(label: 'Open Tester', icon: AppIcons.tester, variant: PillVariant.primary, height: 36, onTap: () => s.toggleRight(true)),
              const SizedBox(width: 8),
              PillButton(label: 'Run history', icon: AppIcons.history, height: 36, onTap: () => s.showTab(ResultsTab.history)),
            ]),
          ]),
        ),
      ),
    );
  }
}

