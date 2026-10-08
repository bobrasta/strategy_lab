import 'package:flutter/material.dart';

import '../data/events.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../util/format.dart';
import 'common.dart';
import 'pills.dart';

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
              Text('XAUUSD', style: ts(13, w: FontWeight.w600, ls: 0.3)),
              const SizedBox(width: 10),
              Text('${s.timeframe} · ${fmtShort(c.time(hb))}', style: ts(12, color: C.mute)),
              if (s.isSample) ...[const SizedBox(width: 10), Text('SAMPLE DATA', style: capsLabel(color: C.gold))],
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

Future<bool> _confirmClear(BuildContext context, int n) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Clear ${fmtInt(n)} predictions?', style: ts(16, w: FontWeight.w500)),
      content: SizedBox(
        width: 360,
        child: Text('This removes every call from this session. Export first if you want to keep them.', style: ts(13, color: C.mute, height: 1.4)),
      ),
      actions: [
        PillButton(label: 'Cancel', onTap: () => Navigator.pop(ctx, false)),
        PillButton(label: 'Clear', color: C.red, borderColor: C.red, onTap: () => Navigator.pop(ctx, true)),
      ],
    ),
  );
  return r ?? false;
}

/// Asks before unlocking hold-out stats. Returns true if revealed.
Future<bool> confirmRevealHoldout(BuildContext context, AppState s) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Reveal the 2026 hold-out?', style: ts(16, w: FontWeight.w500)),
      content: SizedBox(
        width: 400,
        child: Text(
          "Hold-out stats and outcomes become visible for good, and today's date is recorded in fvg_holdout.json. "
          'Only do this once your rules are frozen.',
          style: ts(13, color: C.mute, height: 1.4),
        ),
      ),
      actions: [
        PillButton(label: 'Keep locked', onTap: () => Navigator.pop(ctx, false)),
        PillButton(label: 'Reveal hold-out', color: C.gold, borderColor: C.gold, onTap: () => Navigator.pop(ctx, true)),
      ],
    ),
  );
  if (r == true) await s.revealHoldout();
  return r ?? false;
}

/// Live counters + prediction controls, shown during replay.
class ReplayCounters extends StatelessWidget {
  const ReplayCounters({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final s = state;
    Widget stat(String v, String l) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(v, style: ts(18, w: FontWeight.w300)),
          const SizedBox(height: 2),
          Text(l, style: ts(11, color: C.mute)),
        ]);
    final showPred = s.predict || s.predictionLog.isNotEmpty;
    return Glass(
      radius: 12,
      opacity: 0.82,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: IntrinsicHeight(
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Center(child: Text('REPLAY', style: capsLabel(color: C.gold))),
          const SizedBox(width: 20),
          stat('${s.openGaps}', 'Open gaps'),
          const SizedBox(width: 20),
          stat('${s.resolvedCount}', 'Resolved'),
          const SizedBox(width: 20),
          stat(s.runningBounceRate, 'Bounce rate'),
          if (showPred) ...[
            const SizedBox(width: 20),
            Container(width: 1, color: C.line),
            const SizedBox(width: 20),
            Tooltip(
              message: 'Correct / scored. Only calls whose outcome is already on screen are scored. ${fmtInt(s.predictionLog.length)} calls this session.',
              child: stat(s.score, 'Your calls'),
            ),
            const SizedBox(width: 12),
            Center(
              child: RoundIconButton(
                icon: AppIcons.export,
                tooltip: 'Export predictions',
                enabled: s.predictionLog.isNotEmpty,
                onTap: s.exportPredictions,
              ),
            ),
            Center(
              child: RoundIconButton(
                icon: AppIcons.clear,
                color: C.mute,
                tooltip: 'Clear predictions',
                enabled: s.predictionLog.isNotEmpty,
                onTap: () async {
                  if (await _confirmClear(context, s.predictionLog.length)) s.clearPredictions();
                },
              ),
            ),
          ],
        ]),
      ),
    );
  }
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
        toggle('fvg', 'Zones'),
        toggle('levels', 'Levels'),
        toggle('labels', 'Labels'),
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
            message: 'Starts 50 bars before the selected gap forms',
            child: PillButton(
              label: 'Replay this event',
              icon: AppIcons.replayEvent,
              height: 28,
              fontSize: 12,
              variant: PillVariant.ghost,
              enabled: s.selected != null && s.zoneFor(s.selected!) != null,
              onTap: s.replaySelected,
            ),
          ),
          const VDivider(height: 16),
          const SizedBox(width: 6),
          Text('Predict', style: ts(12)),
          const SizedBox(width: 8),
          PillSwitch(value: s.predict, onChanged: (_) => s.togglePredict(), width: 28, height: 16),
          const SizedBox(width: 6),
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
    final status = s.peek != null ? 'waiting for your call' : (s.playing ? 'playing' : 'paused');
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
              enabled: s.peek == null,
              onTap: s.togglePlay,
            ),
            const SizedBox(width: 2),
            RoundIconButton(icon: AppIcons.stepFwd, size: 36, iconSize: 20, tooltip: 'Step forward (→) · Shift+→ next FVG event', onTap: () => s.step(1)),
            const SizedBox(width: 4),
            PillButton(label: 'Next touch', icon: AppIcons.nextTouch, height: 32, fontSize: 12, variant: PillVariant.ghost, trailing: const Kbd('N'), onTap: s.nextTouch),
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

/// Shown while paused before a first-touch bar. Reveals nothing about the outcome.
class PredictPrompt extends StatelessWidget {
  const PredictPrompt({super.key, required this.state, required this.ev});
  final AppState state;
  final FvgEvent ev;

  @override
  Widget build(BuildContext context) {
    final s = state;
    return Glass(
      opacity: 0.95,
      shadow: true,
      borderColor: C.gold.withOpacity(0.45),
      padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('NEXT BAR TOUCHES THE GAP · YOUR CALL', style: capsLabel(color: C.gold)),
          const SizedBox(height: 2),
          Text(
            '${ev.isBull ? 'Bullish' : 'Bearish'} · ${ev.gapAtr.toStringAsFixed(2)}× ATR · ${ev.sizeQ} · ${ev.session} · waited ${ev.age} bars',
            style: ts(13),
          ),
        ]),
        const SizedBox(width: 16),
        PillButton(label: 'Bounce', height: 40, fontSize: 14, color: C.green, borderColor: C.green, tint: C.green.withOpacity(0.08), onTap: () => s.guess('bounce')),
        const SizedBox(width: 6),
        PillButton(label: 'Break', height: 40, fontSize: 14, color: C.red, borderColor: C.red, tint: C.red.withOpacity(0.08), onTap: () => s.guess('break')),
      ]),
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

/// Selected event in Explore: facts, star, note, replay and M1 drill-down.
class EventDetailCard extends StatefulWidget {
  const EventDetailCard({super.key, required this.state, required this.ev});
  final AppState state;
  final FvgEvent ev;
  @override
  State<EventDetailCard> createState() => _EventDetailCardState();
}

class _EventDetailCardState extends State<EventDetailCard> {
  late final TextEditingController _note = TextEditingController(text: widget.state.bookmarks.note(widget.ev.id));

  @override
  void didUpdateWidget(EventDetailCard old) {
    super.didUpdateWidget(old);
    if (old.ev.id != widget.ev.id) _note.text = widget.state.bookmarks.note(widget.ev.id);
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Widget _fact(String k, String v) => Container(
        height: 20,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        alignment: Alignment.center,
        decoration: BoxDecoration(border: Border.all(color: C.line), borderRadius: BorderRadius.circular(999)),
        child: Text.rich(TextSpan(children: [
          TextSpan(text: '$k ', style: ts(11, color: C.mute)),
          TextSpan(text: v, style: ts(11)),
        ])),
      );

  @override
  Widget build(BuildContext context) {
    final s = widget.state, ev = widget.ev, starred = s.bookmarks.starred(ev.id), locked = s.outcomeHidden(ev);
    return Glass(
      radius: 16,
      opacity: 0.95,
      shadow: true,
      padding: const EdgeInsets.all(14),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(ev.isBull ? AppIcons.bull : AppIcons.bear, size: 14, color: C.mute),
          const SizedBox(width: 6),
          Expanded(child: Text('${ev.isBull ? 'Bullish' : 'Bearish'} gap · ${ev.time}', overflow: TextOverflow.ellipsis, style: ts(13, w: FontWeight.w500))),
          RoundIconButton(icon: starred ? AppIcons.star : AppIcons.starOutline, color: starred ? C.gold : C.mute, tooltip: 'Star', onTap: () => s.toggleStar(ev.id)),
          RoundIconButton(icon: AppIcons.close, color: C.mute, onTap: () => s.select(null)),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: [
          if (locked) _fact('Hold-out', 'locked') else ...[scenarioPill(ev.scenario), outcomePill(ev.outcome)],
          _fact('Gap', '${ev.gapAtr.toStringAsFixed(2)}× ATR'),
          _fact('Size', ev.sizeQ),
          if (ev.dispQ != null) _fact('Displacement', ev.dispQ!),
          _fact('Formed', ev.session),
          if (ev.touchSession != null) _fact('Touched', ev.touchSession!),
          if (ev.htfTrend != null) _fact('HTF', ev.htfTrend!),
          if (ev.sweep != null) _fact('Sweep', ev.sweep! ? 'yes' : 'no'),
          _fact('Waited', '${ev.age}'),
          _fact('Period', periodLabel(ev.period)),
          if (!locked) ...[
            _fact('Max wick', ev.maxWick.toStringAsFixed(2)),
            _fact('Max close', ev.maxClose.toStringAsFixed(2)),
            if (ev.bars != null) _fact('Resolved in', '${ev.bars}'),
          ],
        ]),
        const SizedBox(height: 10),
        Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(border: Border.all(color: C.line), borderRadius: BorderRadius.circular(999)),
          child: TextField(
            controller: _note,
            onChanged: (t) => s.setNote(ev.id, t),
            style: ts(12),
            decoration: InputDecoration.collapsed(hintText: 'Add a one-line note', hintStyle: ts(12, color: C.mute)),
          ),
        ),
        const SizedBox(height: 10),
        Row(children: [
          PillButton(
            label: 'Replay this event',
            icon: AppIcons.replayEvent,
            height: 30,
            fontSize: 12,
            enabled: s.zoneFor(ev.id) != null && s.drill == null,
            onTap: s.replaySelected,
          ),
          const SizedBox(width: 6),
          if (s.drill == null)
            Tooltip(
              message: s.hasM1 ? 'Formation to resolution on M1' : 'Load an M1 candle file to drill down',
              child: PillButton(label: 'View on M1', icon: AppIcons.drill, height: 30, fontSize: 12, enabled: s.hasM1, onTap: s.viewOnM1),
            )
          else
            PillButton(label: 'Back to ${s.drill!.prevTf}', height: 30, fontSize: 12, trailing: const Kbd('Esc'), onTap: s.exitDrill),
        ]),
      ]),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) => CustomPaint(
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
                child: const Icon(AppIcons.data, size: 20, color: C.mute),
              ),
              const SizedBox(height: 20),
              Text(
                state.eventsLoaded
                    ? 'Events loaded. Load the candle file they were computed on to see them on the chart.'
                    : 'Load XAUUSD candles and fvg_events.csv from your Python study to start.',
                style: ts(15),
              ),
              const SizedBox(height: 20),
              Row(mainAxisSize: MainAxisSize.min, children: [
                PillButton(label: 'Load candles', icon: AppIcons.upload, variant: PillVariant.primary, height: 36, enabled: state.busy == null, onTap: state.pickCandles),
                const SizedBox(width: 8),
                PillButton(label: 'Load events', icon: AppIcons.upload, height: 36, enabled: state.busy == null, onTap: state.pickEvents),
              ]),
            ]),
          ),
        ),
      );
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

/// Exposed for the events table.
EvOutcome? visibleOutcome(AppState s, FvgEvent e) {
  if (s.outcomeHidden(e)) return null;
  return s.isReplay && !s.selectMode && (!e.mapped || e.endIdx > s.visibleCursor) ? null : e.outcome;
}
