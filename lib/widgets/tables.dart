import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme.dart';
import '../util/format.dart';
import 'common.dart';
import 'fields.dart';

class Col {
  const Col(this.title, this.flex, {this.right = false});
  final String title;
  final int flex;
  final bool right;
}

/// Header + virtualised rows; rows are built lazily, so 50k deals cost nothing until scrolled to.
class DataTableView extends StatelessWidget {
  const DataTableView({super.key, required this.cols, required this.count, required this.cell, this.onTap, this.selected, this.controller, this.widgetCell});
  final List<Col> cols;
  final int count;
  final (String, Color?) Function(int row, int col) cell;
  final void Function(int row)? onTap;
  final bool Function(int row)? selected;
  final ScrollController? controller;

  /// A widget instead of text for some cells (e.g. a checkbox with its own tap).
  final Widget? Function(int row, int col)? widgetCell;

  @override
  Widget build(BuildContext context) => Column(children: [
        Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: const BoxDecoration(border: Border.symmetric(horizontal: BorderSide(color: C.line))),
          child: Row(children: [
            for (final c in cols)
              Expanded(
                flex: c.flex,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(c.title.toUpperCase(), maxLines: 1, overflow: TextOverflow.clip, textAlign: c.right ? TextAlign.right : TextAlign.left, style: capsLabel()),
                ),
              ),
          ]),
        ),
        Expanded(
          child: count == 0
              ? Center(child: Text('Nothing here yet.', style: ts(12, color: C.mute)))
              : ListView.builder(
                  controller: controller,
                  itemCount: count,
                  itemExtent: 30,
                  itemBuilder: (context, i) {
                    final sel = selected?.call(i) ?? false;
                    return HoverBox(
                      onTap: onTap == null ? null : () => onTap!(i),
                      builder: (context, h) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: sel ? C.gold.withOpacity(0.10) : (h ? C.text.withOpacity(0.03) : Colors.transparent),
                          border: const Border(bottom: BorderSide(color: C.rowLine)),
                        ),
                        child: Row(children: [
                          for (var j = 0; j < cols.length; j++)
                            Expanded(
                              flex: cols[j].flex,
                              child: Builder(builder: (_) {
                                final w = widgetCell?.call(i, j);
                                if (w != null) return Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: Align(alignment: Alignment.centerLeft, child: w));
                                final (text, color) = cell(i, j);
                                return Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 6),
                                  child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: cols[j].right ? TextAlign.right : TextAlign.left, style: ts(12, color: color ?? (sel ? C.gold : C.text))),
                                );
                              }),
                            ),
                        ]),
                      ),
                    );
                  },
                ),
        ),
      ]);
}

/// Replay shows only what's stamped at or before the cursor.
bool _replayCut(AppState s) => s.isReplay && !s.selectMode;

class TradesTable extends StatelessWidget {
  const TradesTable({super.key, required this.state});
  final AppState state;

  static const cols = [
    Col('#', 4),
    Col('Type', 4),
    Col('Vol', 4, right: true),
    Col('Open time', 11),
    Col('Open', 6, right: true),
    Col('SL', 6, right: true),
    Col('TP', 6, right: true),
    Col('Close time', 11),
    Col('Close', 6, right: true),
    Col('Reason', 6),
    Col('Flags', 9),
    Col('Net', 7, right: true),
    Col('R', 5, right: true),
    Col('MAE R', 5, right: true),
    Col('MFE R', 5, right: true),
    Col('Comment', 10),
  ];

  @override
  Widget build(BuildContext context) {
    final s = state, run = s.run!;
    final cut = _replayCut(s), now = s.nowMs;
    final n = cut ? run.tradesOpenedBy(now) : run.trades.length;
    String px(double v) => v == 0 ? '—' : v.toStringAsFixed(3);
    String r(double? v) => v == null ? '—' : v.toStringAsFixed(2);
    return Column(children: [
      _TabBar(children: [
        Text(cut ? '${fmtInt(n)} trades opened so far' : '${fmtInt(n)} trades', style: ts(12, color: C.mute)),
        const Spacer(),
        PillButton(
          label: 'Replay trade',
          icon: AppIcons.replayEvent,
          height: 28,
          fontSize: 12,
          enabled: s.selectedTrade != null,
          onTap: () => s.replayTrade(s.selectedTrade!),
        ),
      ]),
      Expanded(
        child: DataTableView(
          cols: cols,
          count: n,
          selected: (i) => run.trades[n - 1 - i].ticket == s.selectedTrade,
          onTap: (i) => s.selectTrade(run.trades[n - 1 - i].ticket, reveal: true),
          cell: (i, j) {
            final t = run.trades[n - 1 - i]; // newest first
            final shut = !cut || t.closeMs <= now; // exit known only once reached
            return switch (j) {
              0 => ('${t.ticket}', C.mute),
              1 => (t.isBuy ? 'Buy' : 'Sell', null),
              2 => ('${t.volume}', null),
              3 => (t.openTime, null),
              4 => (px(t.openPrice), null),
              5 => (px(t.slInitial), null),
              6 => (px(t.tpInitial), null),
              7 => (shut ? t.closeTime : 'open', shut ? null : C.mute),
              8 => (shut ? px(t.closePrice) : '—', null),
              9 => (shut ? t.reason : '—', C.mute),
              10 => (shut ? t.flags.replaceAll('|', ' ') : '', C.gold),
              11 => (shut ? fmtMoneySigned(t.net) : '—', shut ? (t.net > 0 ? C.green : C.red) : C.mute),
              12 => (shut ? r(t.r) : '—', null),
              13 => (shut ? r(t.value('mae_r')) : '—', C.mute),
              14 => (shut ? r(t.value('mfe_r')) : '—', C.mute),
              _ => (t.comment, C.mute),
            };
          },
        ),
      ),
    ]);
  }
}

class DealsTable extends StatelessWidget {
  const DealsTable({super.key, required this.state});
  final AppState state;

  static const _show = ['ticket', 'time', 'type', 'entry', 'volume', 'price', 'position', 'reason', 'commission', 'swap', 'profit', 'balance', 'comment'];
  static const _flex = {'ticket': 4, 'time': 11, 'type': 4, 'entry': 4, 'volume': 4, 'price': 6, 'position': 5, 'reason': 5, 'commission': 6, 'swap': 6, 'profit': 7, 'balance': 8, 'comment': 12};
  static const _money = {'commission', 'swap', 'profit', 'balance'};

  @override
  Widget build(BuildContext context) {
    final s = state, d = s.run!.data;
    final n = _replayCut(s) ? s.run!.dealsBy(s.nowMs) : d.deals.length;
    final idx = [for (final k in _show) d.dealHeader.indexOf(k)];
    return Column(children: [
      _TabBar(children: [Text('${fmtInt(n)} deals${_replayCut(s) ? ' so far' : ''}', style: ts(12, color: C.mute))]),
      Expanded(
        child: DataTableView(
          cols: [for (final k in _show) Col(k, _flex[k]!, right: const {'volume', 'price', 'commission', 'swap', 'profit', 'balance'}.contains(k))],
          count: n,
          cell: (i, j) {
            final row = d.deals[n - 1 - i].cells, k = idx[j];
            final raw = k < 0 || k >= row.length ? '' : row[k];
            final name = _show[j];
            if (_money.contains(name)) {
              final v = double.tryParse(raw);
              return (fmtMoney(v), name == 'profit' && v != null && v != 0 ? (v > 0 ? C.green : C.red) : null);
            }
            if (name == 'price') return (double.tryParse(raw)?.toStringAsFixed(3) ?? raw, null);
            return (raw, name == 'ticket' || name == 'comment' ? C.mute : null);
          },
        ),
      ),
    ]);
  }
}

class JournalView extends StatefulWidget {
  const JournalView({super.key, required this.state});
  final AppState state;
  @override
  State<JournalView> createState() => _JournalViewState();
}

class _JournalViewState extends State<JournalView> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final s = widget.state, j = s.run!.data.journal;
    final n = _replayCut(s) ? s.run!.journalBy(s.nowMs) : j.length;
    final q = _q.trim().toLowerCase();
    final rows = q.isEmpty ? null : [for (var i = 0; i < n; i++) if (j[i].text.toLowerCase().contains(q)) i];
    final count = rows?.length ?? n;
    return Column(children: [
      _TabBar(children: [
        Text('${fmtInt(count)} lines${_replayCut(s) ? ' so far' : ''}', style: ts(12, color: C.mute)),
        const Spacer(),
        PillField(value: _q, hint: 'Search the journal', width: 240, onChanged: (v) => setState(() => _q = v)),
      ]),
      Expanded(
        child: DataTableView(
          cols: const [Col('Time (UTC)', 12), Col('Message', 60)],
          count: count,
          cell: (i, c) {
            final l = j[rows == null ? i : rows[i]];
            return c == 0 ? (formatKeyMs(l.ms), C.mute) : (l.text, l.text.contains('retcode') || l.text.contains('reject') ? C.gold : null);
          },
        ),
      ),
    ]);
  }
}

String formatKeyMs(int ms) {
  final t = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  String p(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${p(t.month)}-${p(t.day)} ${p(t.hour)}:${p(t.minute)}:${p(t.second)}';
}

class _TabBar extends StatelessWidget {
  const _TabBar({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 40,
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Row(children: children)),
      );
}

/// Trades the Trades tab lists (opened by the cursor in replay).
int tradesShown(AppState s) => _replayCut(s) ? s.run!.tradesOpenedBy(s.nowMs) : s.run!.trades.length;

