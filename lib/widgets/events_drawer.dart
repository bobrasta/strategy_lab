import 'package:flutter/material.dart';

import '../data/events.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../util/format.dart';
import 'chart_overlays.dart' show visibleOutcome;
import 'common.dart';
import 'pills.dart';

const _cols = ['', 'Formed', 'Dir', 'Gap × ATR', 'Waited', 'Max wick', 'Max close', 'Scenario', 'Outcome', 'Bars', 'Note'];
const _flex = [3, 13, 6, 7, 6, 7, 7, 17, 8, 6, 14];
const _right = {3, 4, 5, 6, 9};

class EventsHandle extends StatelessWidget {
  const EventsHandle({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onVerticalDragUpdate: (d) {
          if (d.delta.dy < -4 && !state.bottomOpen) state.toggleBottom();
        },
        child: HoverBox(
          onTap: state.eventsLoaded ? state.toggleBottom : null,
          builder: (context, h) => Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(color: C.panel, borderRadius: BorderRadius.circular(16), border: Border.all(color: h ? C.lineHover : C.line)),
            child: Row(children: [
              Expanded(
                child: Row(children: [
                  Text('Events', style: ts(13, w: FontWeight.w500)),
                  const SizedBox(width: 8),
                  Text('·  ${state.eventsLoaded ? fmtInt(state.stats.total) : '—'}', style: ts(13, color: C.mute)),
                ]),
              ),
              Container(width: 36, height: 4, decoration: BoxDecoration(color: C.line, borderRadius: BorderRadius.circular(999))),
              Expanded(
                child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  Text('Open table', style: ts(12, color: C.mute)),
                  const SizedBox(width: 6),
                  const Icon(AppIcons.up, size: 14, color: C.mute),
                ]),
              ),
            ]),
          ),
        ),
      );
}

class EventsDrawer extends StatefulWidget {
  const EventsDrawer({super.key, required this.state});
  final AppState state;
  @override
  State<EventsDrawer> createState() => _EventsDrawerState();
}

class _EventsDrawerState extends State<EventsDrawer> {
  late final TextEditingController _q = TextEditingController(text: widget.state.search);

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final q = s.search.trim().toLowerCase();
    final replayCut = s.isReplay && !s.selectMode && s.zonesOnChart;
    final cur = s.visibleCursor;
    // In replay, hide events that haven't formed yet (on the events timeframe).
    final rows = s.filtered.reversed.where((e) {
      if (replayCut && (!e.mapped || e.formedIdx > cur)) return false;
      if (q.isEmpty) return true;
      return '${e.time} ${e.dirCode} ${scenarioLabel(e.scenario)} ${e.session} ${e.sizeQ} ${s.bookmarks.note(e.id)}'.toLowerCase().contains(q);
    }).toList();

    return Panel(
      shadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 48, offset: Offset(0, -16))],
      child: Column(children: [
        SizedBox(
          height: 48,
          child: Stack(children: [
            Positioned(
              top: 6,
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: s.toggleBottom,
                  onVerticalDragUpdate: (d) {
                    if (d.delta.dy > 4) s.toggleBottom();
                  },
                  child: Container(width: 36, height: 4, decoration: BoxDecoration(color: C.line, borderRadius: BorderRadius.circular(999))),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 12),
              child: Row(children: [
                Text('Events', style: ts(13, w: FontWeight.w500)),
                const SizedBox(width: 10),
                Text('${fmtInt(s.stats.total)} first touches · ${fmtInt(rows.length)} shown', style: ts(13, color: C.mute)),
                const Spacer(),
                PillButton(
                  label: 'Replay this event',
                  icon: AppIcons.replayEvent,
                  height: 30,
                  fontSize: 12,
                  enabled: s.selected != null && s.zoneFor(s.selected!) != null,
                  onTap: s.replaySelected,
                ),
                const SizedBox(width: 12),
                Container(
                  height: 30,
                  width: 220,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(border: Border.all(color: C.line), borderRadius: BorderRadius.circular(999)),
                  child: Row(children: [
                    const Icon(AppIcons.search, size: 14, color: C.mute),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _q,
                        onChanged: s.setSearch,
                        style: ts(12),
                        decoration: InputDecoration.collapsed(hintText: 'Search events and notes', hintStyle: ts(12, color: C.mute)),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(width: 12),
                RoundIconButton(icon: AppIcons.down, size: 30, color: C.mute, tooltip: 'Collapse', onTap: s.toggleBottom),
              ]),
            ),
          ]),
        ),
        Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: const BoxDecoration(border: Border.symmetric(horizontal: BorderSide(color: C.line))),
          child: Row(children: [
            for (var i = 0; i < _cols.length; i++)
              Expanded(
                flex: _flex[i],
                child: Text(_cols[i].toUpperCase(), textAlign: _right.contains(i) ? TextAlign.right : TextAlign.left, style: capsLabel()),
              ),
          ]),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: rows.length,
            itemExtent: 34,
            itemBuilder: (context, i) => _Row(key: ValueKey(rows[i].id), state: s, ev: rows[i]),
          ),
        ),
      ]),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({super.key, required this.state, required this.ev});
  final AppState state;
  final FvgEvent ev;

  @override
  Widget build(BuildContext context) {
    final s = state, sel = s.selected == ev.id, starred = s.bookmarks.starred(ev.id);
    final shown = visibleOutcome(s, ev); // null while unresolved at the replay cursor
    final touchedNow = !(s.isReplay && !s.selectMode) || (ev.mapped && ev.touchIdx <= s.visibleCursor);
    String hide(String v) => shown == null ? '—' : v;
    Widget cell(String v, {Color color = C.text}) => Text(v, textAlign: TextAlign.right, style: ts(12, color: color));

    return HoverBox(
      onTap: () => s.select(ev.id, reveal: true),
      builder: (context, h) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: sel ? C.gold.withOpacity(0.10) : (h ? C.text.withOpacity(0.03) : Colors.transparent),
          border: const Border(bottom: BorderSide(color: C.rowLine)),
        ),
        child: Row(children: [
          Expanded(
            flex: _flex[0],
            child: Align(
              alignment: Alignment.centerLeft,
              child: RoundIconButton(
                icon: starred ? AppIcons.star : AppIcons.starOutline,
                size: 24,
                iconSize: 15,
                color: starred ? C.gold : C.mute,
                onTap: () => s.toggleStar(ev.id),
              ),
            ),
          ),
          Expanded(flex: _flex[1], child: Text(ev.time, overflow: TextOverflow.ellipsis, style: ts(12, color: sel ? C.gold : C.text))),
          Expanded(
            flex: _flex[2],
            child: Row(children: [
              Icon(ev.isBull ? AppIcons.bull : AppIcons.bear, size: 13, color: C.mute),
              const SizedBox(width: 4),
              Text(ev.isBull ? 'Bull' : 'Bear', style: ts(12)),
            ]),
          ),
          Expanded(flex: _flex[3], child: cell(ev.gapAtr.toStringAsFixed(2))),
          Expanded(flex: _flex[4], child: cell(touchedNow ? '${ev.age}' : '—')),
          Expanded(flex: _flex[5], child: cell(hide(ev.maxWick.toStringAsFixed(2)))),
          Expanded(flex: _flex[6], child: cell(hide(ev.maxClose.toStringAsFixed(2)))),
          Expanded(
            flex: _flex[7],
            child: Padding(
              padding: const EdgeInsets.only(left: 16, right: 8),
              child: Align(alignment: Alignment.centerLeft, child: scenarioPill(shown == null ? null : ev.scenario)),
            ),
          ),
          Expanded(flex: _flex[8], child: Align(alignment: Alignment.centerLeft, child: outcomePill(shown))),
          Expanded(flex: _flex[9], child: cell(shown == null || ev.bars == null ? '—' : '${ev.bars}', color: C.mute)),
          Expanded(flex: _flex[10], child: Padding(padding: const EdgeInsets.only(left: 16), child: _NoteCell(state: s, id: ev.id))),
        ]),
      ),
    );
  }
}

class _NoteCell extends StatefulWidget {
  const _NoteCell({required this.state, required this.id});
  final AppState state;
  final String id;
  @override
  State<_NoteCell> createState() => _NoteCellState();
}

class _NoteCellState extends State<_NoteCell> {
  late final TextEditingController _c = TextEditingController(text: widget.state.bookmarks.note(widget.id));
  final FocusNode _f = FocusNode();

  @override
  void didUpdateWidget(_NoteCell old) {
    super.didUpdateWidget(old);
    final v = widget.state.bookmarks.note(widget.id);
    if (!_f.hasFocus && _c.text != v) _c.text = v;
  }

  @override
  void dispose() {
    _c.dispose();
    _f.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _c,
        focusNode: _f,
        onChanged: (t) => widget.state.setNote(widget.id, t),
        style: ts(12),
        decoration: InputDecoration.collapsed(hintText: 'Add note', hintStyle: ts(12, color: C.line)),
      );
}
