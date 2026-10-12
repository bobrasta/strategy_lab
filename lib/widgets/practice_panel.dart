import 'package:flutter/material.dart';

import '../practice/practice_state.dart';
import '../run/protection.dart';
import '../state/lab_state.dart';
import '../theme.dart';
import '../util/format.dart';
import 'common.dart';
import 'fields.dart';
import 'tester_panel.dart' show baseNameOf;

/// Practice (M8): trade by hand in replay, as in MT5's order window. The engine executes every request
/// on the next tick and reports fills, P&L and the account; this panel only shows them.
class PracticePanel extends StatefulWidget {
  const PracticePanel({super.key, required this.lab});
  final LabState lab;

  @override
  State<PracticePanel> createState() => _PracticePanelState();
}

class _PracticePanelState extends State<PracticePanel> {
  String _date = '';
  String _deposit = '';
  String _leverage = '';

  LabState get lab => widget.lab;
  PracticeState get p => lab.practice;

  @override
  Widget build(BuildContext context) {
    final s = lab.chart;
    return Panel(
      key: const ValueKey('practice-panel'),
      shadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 48, offset: Offset(-16, 0))],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 10, 6),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Practice', style: ts(15, w: FontWeight.w500)),
                const SizedBox(height: 2),
                Text('Trade by hand in replay · the engine fills every order', overflow: TextOverflow.ellipsis, style: ts(11, color: C.mute)),
              ]),
            ),
            RoundIconButton(icon: AppIcons.close, color: C.mute, tooltip: 'Close', onTap: () => s.togglePractice(false)),
          ]),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
            child: p.active ? _session() : _setup(),
          ),
        ),
      ]),
    );
  }

  // ── before a session ────────────────────────────────────────────────
  Widget _setup() {
    final saved = p.saved, ready = lab.engine.ready;
    final date = _date.trim();
    final validDate = isIsoDate(date);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (p.error != null) ...[_box(p.error!, C.red), const SizedBox(height: 12)],
      if (p.message != null) ...[_box(p.message!, p.messageIsError ? C.red : C.mute), const SizedBox(height: 12)],
      if (saved != null) ...[
        const SectionLabel('Saved session'),
        const SizedBox(height: 8),
        Text(baseNameOf('${saved['out']}'), style: ts(12.5)),
        const SizedBox(height: 2),
        _note('From ${saved['from']} on ${baseNameOf('${saved['data']}')}'
            '${saved['reached_ms'] is num && (saved['reached_ms'] as num) > 0 ? ', reached ${fmtDock(DateTime.fromMillisecondsSinceEpoch((saved['reached_ms'] as num).toInt(), isUtc: true))}' : ''}.'),
        const SizedBox(height: 8),
        Row(children: [
          PillButton(
            key: const ValueKey('practice-resume'),
            label: p.starting ? 'Resuming…' : 'Resume',
            icon: AppIcons.play,
            variant: PillVariant.primary,
            height: 30,
            fontSize: 12,
            enabled: ready && !p.starting,
            onTap: () => p.start(
              data: '${saved['data']}',
              startDate: '${saved['from']}',
              opts: {for (final e in ((saved['options'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}'},
              resume: true,
            ),
          ),
          const SizedBox(width: 8),
          PillButton(label: 'Discard', height: 30, fontSize: 12, variant: PillVariant.ghost, enabled: !p.starting, onTap: p.discardSaved),
        ]),
        const SizedBox(height: 20),
      ],
      const SectionLabel('New session'),
      const SizedBox(height: 6),
      FormRow(label: 'Data', child: Text(baseNameOf(lab.settings.dataFile), overflow: TextOverflow.ellipsis, style: ts(12))),
      FormRow(
        label: 'Start date',
        sub: _date.isEmpty ? 'UTC, YYYY-MM-DD. You see the market up to it; step forward to trade.' : (validDate ? null : 'Use YYYY-MM-DD.'),
        subColor: validDate || _date.isEmpty ? C.mute : C.red,
        child: Row(children: [
          PillField(value: _date, hint: 'YYYY-MM-DD', width: 130, error: _date.isNotEmpty && !validDate, fieldKey: const ValueKey('practice-date'), onChanged: (v) => setState(() => _date = v)),
          const SizedBox(width: 8),
          PillButton(key: const ValueKey('practice-random'), label: 'Random', height: 30, fontSize: 12, variant: PillVariant.ghost, onTap: _random),
        ]),
      ),
      FormRow(
        label: 'Deposit',
        child: PillField(value: _deposit, hint: lab.settings.deposit.isEmpty ? '10000' : lab.settings.deposit, width: 130, onChanged: (v) => setState(() => _deposit = v)),
      ),
      FormRow(
        label: 'Leverage',
        child: PillField(value: _leverage, hint: lab.settings.leverage.isEmpty ? '100' : lab.settings.leverage, width: 130, onChanged: (v) => setState(() => _leverage = v)),
      ),
      FormRow(label: 'Costs', child: _note('The Tester\'s profile and cost overrides.')),
      const SizedBox(height: 10),
      Row(children: [
        PillButton(
          key: const ValueKey('practice-start'),
          label: p.starting ? 'Starting…' : 'Start practice',
          icon: AppIcons.play,
          variant: PillVariant.primary,
          height: 32,
          enabled: ready && validDate && !p.starting,
          onTap: () => _start(date),
        ),
      ]),
      if (!ready) ...[const SizedBox(height: 8), _note('Waiting for the engine.')],
    ]);
  }

  void _random() {
    final c = lab.chart.candles;
    final first = c != null && lab.chart.candlesPath == lab.settings.dataFile ? c.t[0] : DateTime.utc(2021).millisecondsSinceEpoch;
    final last = c != null && lab.chart.candlesPath == lab.settings.dataFile ? c.t[c.length - 1] : DateTime.utc(2023, 12, 31).millisecondsSinceEpoch;
    final d = PracticeState.randomStart(first, last, lab.settings.protectionFor(kPracticeKey));
    if (d != null) setState(() => _date = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}');
  }

  Map<String, String> _options() => {
        ...lab.settings.costs,
        'deposit': _deposit.trim().isNotEmpty ? _deposit.trim() : (lab.settings.deposit.isEmpty ? '10000' : lab.settings.deposit),
        'leverage': _leverage.trim().isNotEmpty ? _leverage.trim() : (lab.settings.leverage.isEmpty ? '100' : lab.settings.leverage),
      };

  Future<void> _start(String date) async {
    final prot = p.protectedAtStart(date);
    if (prot != null) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          key: const ValueKey('practice-protected-dialog'),
          backgroundColor: C.panel,
          title: Text('Protected period', style: ts(15, w: FontWeight.w500)),
          content: SizedBox(
            width: 420,
            child: Text(
              'Practice is protected from ${prot.label}. Starting on $date shows price action from that period, '
              'which can bias a later hold-out test. Your confirmation is logged with a timestamp in the session folder.',
              style: ts(12.5, height: 1.45),
            ),
          ),
          actions: [
            PillButton(label: 'Cancel', variant: PillVariant.ghost, onTap: () => Navigator.of(ctx).pop(false)),
            PillButton(key: const ValueKey('practice-protected-confirm'), label: 'Practise anyway', variant: PillVariant.primary, onTap: () => Navigator.of(ctx).pop(true)),
          ],
        ),
      );
      if (ok != true) return;
    }
    await p.start(data: lab.settings.dataFile, startDate: date, opts: _options(), confirmed: prot);
  }

  // ── during a session ────────────────────────────────────────────────
  Widget _session() {
    final t = p.ticket;
    final pos = p.position;
    final engineAt = p.engineMs == null ? null : DateTime.fromMillisecondsSinceEpoch(p.engineMs!, isUtc: true);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(baseNameOf(p.out ?? ''), overflow: TextOverflow.ellipsis, style: ts(12.5)),
      const SizedBox(height: 2),
      _note(engineAt == null ? 'Step forward to the first bar of ${p.from} to start trading.' : 'Engine at ${fmtDock(engineAt)} UTC${p.busy ? ' · working…' : ''}'),
      if (p.needsConfirm != null) ...[const SizedBox(height: 12), _protectedCard(p.needsConfirm!)],
      if (!p.atHead && p.needsConfirm == null) ...[
        const SizedBox(height: 12),
        Container(
          key: const ValueKey('practice-looking-back'),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(border: Border.all(color: C.line), borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Expanded(child: _note('Looking back. Orders only at the newest bar reached.')),
            PillButton(key: const ValueKey('practice-back-to-latest'), label: 'Back to latest', height: 28, fontSize: 12, onTap: p.backToLatest),
          ]),
        ),
      ],
      if (p.message != null) ...[
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: _box(p.message!, p.messageIsError ? C.red : C.mute, key: const ValueKey('practice-message'))),
          RoundIconButton(icon: AppIcons.close, size: 24, iconSize: 14, color: C.mute, onTap: p.clearMessage),
        ]),
      ],
      const SizedBox(height: 16),
      const SectionLabel('Account'),
      const SizedBox(height: 6),
      _kv('Balance', fmtMoney(p.balance), key: 'practice-balance'),
      _kv('Equity', fmtMoney(p.equity), key: 'practice-equity'),
      _kv('Floating P&L', fmtMoneySigned(p.profit), color: p.profit > 0 ? C.green : (p.profit < 0 ? C.red : C.text)),
      _kv('Margin', fmtMoney(p.margin)),
      _kv('Free margin', fmtMoney(p.freeMargin)),
      const SizedBox(height: 16),
      const SectionLabel('Order'),
      const SizedBox(height: 8),
      Segmented<String>(
        values: const ['market', 'limit', 'stop'],
        selected: t.kind,
        labelOf: (k) => switch (k) { 'market' => 'Market', 'limit' => 'Limit', _ => 'Stop' },
        onChanged: (k) => p.setTicket((x) => x.kind = k),
        height: 26,
        fontSize: 12,
      ),
      const SizedBox(height: 6),
      FormRow(
        label: 'Size',
        labelWidth: 80,
        child: Row(children: [
          PillField(value: t.size, width: 90, fieldKey: const ValueKey('practice-size'), onChanged: (v) => p.setTicket((x) => x.size = v)),
          const SizedBox(width: 8),
          Segmented<String>(
            values: const ['lots', 'risk'],
            selected: t.sizeMode,
            labelOf: (k) => k == 'lots' ? 'Lots' : 'Risk %',
            onChanged: (k) => p.setTicket((x) => x.sizeMode = k),
            height: 26,
            fontSize: 12,
            padH: 10,
          ),
        ]),
      ),
      if (t.kind != 'market') _priceRow('Price', 'price', t.price, (v) => p.setTicket((x) => x.price = v)),
      _priceRow('Stop loss', 'sl', t.sl, (v) => p.setTicket((x) => x.sl = v)),
      _priceRow('Take profit', 'tp', t.tp, (v) => p.setTicket((x) => x.tp = v)),
      if (t.kind != 'market')
        FormRow(
          label: 'Expires',
          labelWidth: 80,
          child: PillField(value: t.expiration, hint: 'GTC, or YYYY-MM-DD HH:MM', width: 190, onChanged: (v) => p.setTicket((x) => x.expiration = v)),
        ),
      if (t.sizeMode == 'risk') Padding(padding: const EdgeInsets.only(left: 80, top: 2), child: _note('Lots from equity × risk ÷ SL distance, computed by the engine. Needs an SL.')),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
          child: PillButton(
            key: const ValueKey('practice-sell'),
            label: t.kind == 'market' ? 'Sell' : 'Sell ${t.kind}',
            color: C.red,
            borderColor: C.red.withOpacity(0.5),
            height: 34,
            enabled: p.canTrade,
            onTap: () => p.submit(false),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: PillButton(
            key: const ValueKey('practice-buy'),
            label: t.kind == 'market' ? 'Buy' : 'Buy ${t.kind}',
            color: C.green,
            borderColor: C.green.withOpacity(0.5),
            height: 34,
            enabled: p.canTrade,
            onTap: () => p.submit(true),
          ),
        ),
      ]),
      const SizedBox(height: 4),
      _note(t.kind == 'market' ? 'Fills at the next price after this bar (the next bar\'s open).' : 'Waits for its price; drag its line on the chart to move it.'),
      const SizedBox(height: 16),
      const SectionLabel('Position'),
      const SizedBox(height: 6),
      if (pos == null)
        _note('No open position.')
      else
        _PositionCard(key: ValueKey('practice-position-${pos.ticket}'), p: p, pos: pos),
      if (p.orders.isNotEmpty) ...[
        const SizedBox(height: 16),
        const SectionLabel('Pending orders'),
        const SizedBox(height: 6),
        for (final o in p.orders)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              Expanded(
                child: Text(
                  '#${o.ticket} ${o.label} ${o.volume.toStringAsFixed(2)} @ ${fmtPrice(o.price)}'
                  '${o.sl > 0 ? ' · SL ${fmtPrice(o.sl)}' : ''}${o.tp > 0 ? ' · TP ${fmtPrice(o.tp)}' : ''}${o.expiration != null ? ' · until ${o.expiration}' : ''}',
                  style: ts(12, color: o.buy ? C.green : C.red),
                ),
              ),
              PillButton(key: ValueKey('practice-cancel-${o.ticket}'), label: 'Cancel', height: 26, fontSize: 11, enabled: p.canTrade, onTap: () => p.cancelOrder(o.ticket)),
            ]),
          ),
      ],
      const SizedBox(height: 16),
      SectionLabel('Closed trades · ${p.trades.length}'),
      const SizedBox(height: 6),
      for (final tr in p.trades.reversed.where((x) => x.closeMs <= lab.chart.nowMs).take(6))
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Expanded(child: Text('#${tr.ticket} ${tr.type} ${tr.volume.toStringAsFixed(2)} · ${tr.reason}', style: ts(12, color: C.mute))),
            Text(fmtMoneySigned(tr.net), style: ts(12, color: tr.net >= 0 ? C.green : C.red)),
          ]),
        ),
      const SizedBox(height: 16),
      const SectionLabel('Journal'),
      const SizedBox(height: 6),
      for (final l in p.journal.reversed.take(6).toList().reversed) Text(l, style: ts(11, color: C.mute, height: 1.35)),
      const SizedBox(height: 18),
      Row(children: [
        PillButton(key: const ValueKey('practice-pause'), label: 'Pause', height: 30, fontSize: 12, enabled: !p.busy, onTap: () => p.pause('Paused. Resume continues where you were.')),
        const Spacer(),
        PillButton(key: const ValueKey('practice-finish'), label: 'Finish session', variant: PillVariant.primary, height: 30, fontSize: 12, enabled: !p.busy, onTap: _finish),
      ]),
      const SizedBox(height: 6),
      _note('Finish closes the position at the current price, cancels orders and saves the session as a run with its report.'),
    ]);
  }

  Widget _priceRow(String label, String field, String value, ValueChanged<String> onChanged) => FormRow(
        label: label,
        labelWidth: 80,
        child: Row(children: [
          PillField(value: value, hint: field == 'price' ? 'price' : 'none', width: 120, fieldKey: ValueKey('practice-$field'), onChanged: onChanged),
          const SizedBox(width: 6),
          RoundIconButton(
            key: ValueKey('practice-pick-$field'),
            icon: AppIcons.selectBar,
            size: 26,
            iconSize: 14,
            filled: p.picking == field,
            tooltip: 'Click the chart to set it',
            onTap: () => p.startPicking(field),
          ),
        ]),
      );

  Widget _protectedCard(ProtectedPeriod prot) => Container(
        key: const ValueKey('practice-protected'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(border: Border.all(color: C.gold.withOpacity(0.6)), borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Protected period ahead', style: ts(13, w: FontWeight.w500, color: C.gold)),
          const SizedBox(height: 4),
          _note('The next bars are in the practice hold-out (${prot.label}). Continuing is logged with a timestamp in the session folder.'),
          const SizedBox(height: 8),
          Row(children: [
            PillButton(key: const ValueKey('practice-protected-continue'), label: 'Continue into it', height: 28, fontSize: 12, onTap: p.confirmProtected),
            const SizedBox(width: 8),
            PillButton(label: 'Stay before it', height: 28, fontSize: 12, variant: PillVariant.ghost, onTap: p.cancelProtected),
          ]),
        ]),
      );

  Future<void> _finish() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.panel,
        title: Text('Finish the session?', style: ts(15, w: FontWeight.w500)),
        content: Text('The open position closes at the current price and pending orders are cancelled. The session becomes a run in History.',
            style: ts(12.5, height: 1.45)),
        actions: [
          PillButton(label: 'Keep trading', variant: PillVariant.ghost, onTap: () => Navigator.of(ctx).pop(false)),
          PillButton(key: const ValueKey('practice-finish-confirm'), label: 'Finish', variant: PillVariant.primary, onTap: () => Navigator.of(ctx).pop(true)),
        ],
      ),
    );
    if (ok == true) await p.finish();
  }

  static Widget _note(String text) => Text(text, style: ts(12, color: C.mute, height: 1.4));

  static Widget _box(String text, Color color, {Key? key}) => Container(
        key: key,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(border: Border.all(color: color.withOpacity(0.5)), borderRadius: BorderRadius.circular(12)),
        child: Text(text, style: ts(12, color: color == C.mute ? C.text : color, height: 1.4)),
      );

  static Widget _kv(String k, String v, {Color color = C.text, String? key}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Expanded(child: Text(k, style: ts(12, color: C.mute))),
          Text(v, key: key == null ? null : ValueKey(key), style: ts(12.5, color: color)),
        ]),
      );
}

/// The open position: the engine's numbers, SL/TP edit, Close.
class _PositionCard extends StatefulWidget {
  const _PositionCard({super.key, required this.p, required this.pos});
  final PracticeState p;
  final PracticePosition pos;

  @override
  State<_PositionCard> createState() => _PositionCardState();
}

class _PositionCardState extends State<_PositionCard> {
  late String _sl = widget.pos.sl > 0 ? PracticeState.priceText(widget.pos.sl) : '';
  late String _tp = widget.pos.tp > 0 ? PracticeState.priceText(widget.pos.tp) : '';

  @override
  void didUpdateWidget(_PositionCard old) {
    super.didUpdateWidget(old);
    if (old.pos.sl != widget.pos.sl) _sl = widget.pos.sl > 0 ? PracticeState.priceText(widget.pos.sl) : '';
    if (old.pos.tp != widget.pos.tp) _tp = widget.pos.tp > 0 ? PracticeState.priceText(widget.pos.tp) : '';
  }

  @override
  Widget build(BuildContext context) {
    final pos = widget.pos, p = widget.p;
    final open = DateTime.fromMillisecondsSinceEpoch(pos.openMs, isUtc: true);
    double v(String s) => double.tryParse(s.trim()) ?? 0;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(border: Border.all(color: C.line), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text('#${pos.ticket} ${pos.buy ? 'Buy' : 'Sell'} ${pos.volume.toStringAsFixed(2)} @ ${fmtPrice(pos.priceOpen)}',
                style: ts(13, w: FontWeight.w500, color: pos.buy ? C.green : C.red)),
          ),
          Text(fmtMoneySigned(pos.profit), key: const ValueKey('practice-position-profit'), style: ts(13, color: pos.profit >= 0 ? C.green : C.red)),
        ]),
        const SizedBox(height: 2),
        Text('Opened ${fmtDock(open)} · swap ${fmtMoney(pos.swap)} · commission ${fmtMoney(pos.commission)}', style: ts(11, color: C.mute)),
        const SizedBox(height: 8),
        Row(children: [
          Text('SL', style: ts(12, color: C.mute)),
          const SizedBox(width: 6),
          PillField(value: _sl, hint: 'none', width: 100, fieldKey: const ValueKey('practice-pos-sl'), onChanged: (x) => setState(() => _sl = x)),
          const SizedBox(width: 10),
          Text('TP', style: ts(12, color: C.mute)),
          const SizedBox(width: 6),
          PillField(value: _tp, hint: 'none', width: 100, fieldKey: const ValueKey('practice-pos-tp'), onChanged: (x) => setState(() => _tp = x)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          PillButton(key: const ValueKey('practice-modify'), label: 'Modify', height: 28, fontSize: 12, enabled: p.canTrade, onTap: () => p.modifyPosition(v(_sl), v(_tp))),
          const Spacer(),
          PillButton(key: const ValueKey('practice-close'), label: 'Close position', height: 28, fontSize: 12, enabled: p.canTrade, onTap: p.closePosition),
        ]),
      ]),
    );
  }
}
