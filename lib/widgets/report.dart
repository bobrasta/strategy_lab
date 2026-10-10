import 'package:flutter/material.dart';

import '../run/run_data.dart';
import '../theme.dart';
import '../util/format.dart';
import 'common.dart';

/// One line of the report: a field of run.json, formatted for display only.
class ReportRow {
  const ReportRow(this.section, this.label, this.value, {this.color});
  final String section, label, value;
  final Color? color;
}

Color? _sign(Object? v) => v is num && v != 0 ? (v > 0 ? C.green : C.red) : null;

/// The MT5 tester report fields plus the engine's own (SPEC §9.3), all read from run.json's summary.
/// Where MT5 shows a percentage the engine doesn't write (e.g. short trades won %), the counts
/// are shown instead: the app never derives numbers.
List<ReportRow> reportRows(RunManifest m) {
  final s = m.summary;
  Object? v(String k) => s[k];
  String money(String k) => fmtMoney((v(k) as num?)?.toDouble());
  String pct(String k) => v(k) is num ? '${fmtNum(v(k))}%' : '—';
  String moneyPct(String a, String b) => '${money(a)} (${pct(b)})';
  String count(String k) => v(k) is num ? fmtInt((v(k) as num).toInt()) : '—';
  final split = (s['pnl_split'] as Map?) ?? const {};
  final exc = (s['excursions'] as Map?) ?? const {};
  String excursion(String g) {
    final e = (exc[g] as Map?) ?? const {};
    return '${fmtNum(e['mae'])} / ${fmtNum(e['mfe'])}  ·  ${fmtNum(e['mae_r'])} R / ${fmtNum(e['mfe_r'])} R';
  }

  const r = 'Results', d = 'Drawdown', t = 'Trades', c = 'Costs and P&L split', p = 'Path and fills';
  return [
    ReportRow(r, 'Total net profit', money('net_profit'), color: _sign(v('net_profit'))),
    ReportRow(r, 'Gross profit', money('gross_profit')),
    ReportRow(r, 'Gross loss', money('gross_loss')),
    ReportRow(r, 'Profit factor', fmtNum(v('profit_factor'))),
    ReportRow(r, 'Expected payoff', money('expected_payoff')),
    ReportRow(r, 'Recovery factor', fmtNum(v('recovery_factor'))),
    ReportRow(r, 'Sharpe ratio', fmtNum(v('sharpe_ratio'))),
    ReportRow(r, 'Average R', fmtNum(v('avg_r'))),
    ReportRow(r, 'OnTester result', fmtNum(v('on_tester'), 4)),
    ReportRow(r, 'Final balance', money('balance')),
    ReportRow(d, 'Balance DD absolute', money('balance_drawdown_absolute')),
    ReportRow(d, 'Balance DD maximal', moneyPct('balance_drawdown_maximal', 'balance_drawdown_maximal_pct')),
    ReportRow(d, 'Balance DD relative', '${pct('balance_drawdown_relative_pct')} (${money('balance_drawdown_relative')})'),
    ReportRow(d, 'Equity DD absolute', money('equity_drawdown_absolute')),
    ReportRow(d, 'Equity DD maximal', moneyPct('equity_drawdown_maximal', 'equity_drawdown_maximal_pct')),
    ReportRow(d, 'Equity DD relative', '${pct('equity_drawdown_relative_pct')} (${money('equity_drawdown_relative')})'),
    ReportRow(d, 'Lowest equity', money('equity_min')),
    ReportRow(t, 'Total trades', count('trades')),
    ReportRow(t, 'Profit / loss trades', '${count('wins')} / ${count('losses')}'),
    ReportRow(t, 'Win rate', pct('win_rate_pct')),
    ReportRow(t, 'Long trades (won)', '${count('long_trades')} (${count('long_wins')})'),
    ReportRow(t, 'Short trades (won)', '${count('short_trades')} (${count('short_wins')})'),
    ReportRow(t, 'Largest profit / loss', '${money('largest_profit_trade')} / ${money('largest_loss_trade')}'),
    ReportRow(t, 'Average profit / loss', '${money('average_profit_trade')} / ${money('average_loss_trade')}'),
    ReportRow(t, 'Max consecutive wins', '${count('max_consecutive_wins')} (${money('max_consecutive_wins_money')})'),
    ReportRow(t, 'Max consecutive losses', '${count('max_consecutive_losses')} (${money('max_consecutive_losses_money')})'),
    ReportRow(t, 'Average holding time', fmtDuration((v('average_holding_seconds') as num?)?.toDouble())),
    ReportRow(t, 'Max holding time', fmtDuration((v('max_holding_seconds') as num?)?.toDouble())),
    ReportRow(c, 'Gross (no costs)', fmtMoney((split['gross'] as num?)?.toDouble())),
    ReportRow(c, 'Spread', fmtMoney((split['spread'] as num?)?.toDouble())),
    ReportRow(c, 'Commission', fmtMoney((split['commission'] as num?)?.toDouble())),
    ReportRow(c, 'Slippage', fmtMoney((split['slippage'] as num?)?.toDouble())),
    ReportRow(c, 'Swap', fmtMoney((split['swap'] as num?)?.toDouble())),
    ReportRow(c, 'MAE / MFE all', excursion('all')),
    ReportRow(c, 'MAE / MFE winners', excursion('winners')),
    ReportRow(c, 'MAE / MFE losers', excursion('losers')),
    ReportRow(p, 'Ambiguous trades', '${count('ambiguous_trades')} (net ${money('ambiguous_net')})'),
    ReportRow(p, 'Same-bar trades', '${count('same_bar_trades')} (net ${money('same_bar_net')})'),
    ReportRow(p, 'Gap fills', count('gap_fills')),
    ReportRow(p, 'Gap losses', '${count('gap_losses')} (avg R ${fmtNum(v('gap_loss_avg_r'))}, net ${money('gap_loss_net')})'),
    ReportRow(p, 'Stop-outs', count('stop_outs')),
    ReportRow(p, 'Closed at end of data', count('closed_at_end_of_data')),
    ReportRow(p, 'Tick path / ambiguity', '${m.model['tick_path'] ?? '—'} / ${m.model['ambiguity_rule'] ?? '—'}'),
    ReportRow(p, 'Bars / ticks', '${count('bars')} / ${count('ticks')}'),
  ];
}

/// The run's settings, for the report header and the compare view.
List<ReportRow> settingRows(RunManifest m) {
  final costs = (m.profile['costs'] as Map?) ?? const {};
  final spread = costs['spread'];
  final slip = costs['slippage'];
  String spreadText() {
    if (spread == null) return '—';
    if (spread is! Map) return '$spread';
    final sessions = (spread['sessions'] as List?)?.length ?? 0;
    return '${spread['mode'] ?? 'points'} ${spread['default'] ?? spread['bps'] ?? ''}${sessions > 0 ? ' + $sessions sessions' : ''}';
  }

  String slipText() => slip == null ? '—' : slip is Map ? [slip['mode'], if (slip['max_points'] != null) 'max ${slip['max_points']}', if (slip['points'] != null) '${slip['points']} pts', 'seed ${slip['seed']}'].join(' ') : '$slip';
  const s = 'Settings';
  final span = m.simSpan;
  return [
    ReportRow(s, 'Strategy', '${m.strategyName} ${m.strategyVersion} (${m.strategyKey})'),
    ReportRow(s, 'Range', '${m.from ?? 'data start'} → ${m.to ?? 'data end'}'),
    ReportRow(s, 'Simulated', span == null ? '—' : '${formatTime(span.$1)} → ${formatTime(m.lastSimMs!)}'),
    ReportRow(s, 'Deposit / leverage', '${fmtMoney((m.account['deposit'] as num?)?.toDouble())} · 1:${m.account['leverage'] ?? '—'}'),
    ReportRow(s, 'Spread', spreadText()),
    ReportRow(s, 'Commission', '${costs['commission_per_lot_side'] ?? '—'} per lot per side'),
    ReportRow(s, 'Slippage', slipText()),
    ReportRow(s, 'Swap', '${costs['swap_mode'] ?? '—'} · long ${costs['swap_long'] ?? '—'} · short ${costs['swap_short'] ?? '—'} · triple ${costs['triple_swap_day'] ?? '—'}'),
    for (final e in m.inputsEffective.entries) ReportRow('Inputs', e.key, e.value, color: m.inputs.containsKey(e.key) ? C.gold : null),
  ];
}

String formatTime(int ms) => fmtFull(DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true));

/// The Backtest tab: the report of one run in sections, MT5 style.
class ReportView extends StatelessWidget {
  const ReportView({super.key, required this.manifest});
  final RunManifest manifest;

  @override
  Widget build(BuildContext context) {
    final m = manifest;
    final rows = [...settingRows(m), ...reportRows(m)];
    final sections = <String, List<ReportRow>>{};
    for (final r in rows) {
      sections.putIfAbsent(r.section, () => []).add(r);
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (m.zeroCost || m.warnings.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Panel(
              color: C.bg,
              radius: 12,
              padding: const EdgeInsets.all(12),
              child: Text(
                [if (m.zeroCost) 'ZERO-COST RUN: no spread, commission, slippage or swap were charged.', ...m.warnings].join('\n'),
                style: ts(12, color: C.gold, height: 1.4),
              ),
            ),
          ),
        LayoutBuilder(builder: (context, c) {
          final cols = c.maxWidth > 1300 ? 4 : (c.maxWidth > 900 ? 3 : 2);
          final w = (c.maxWidth - 12 * (cols - 1)) / cols;
          return Wrap(spacing: 12, runSpacing: 12, children: [
            for (final e in sections.entries) SizedBox(width: w, child: _Section(title: e.key, rows: e.value)),
          ]);
        }),
      ]),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.rows});
  final String title;
  final List<ReportRow> rows;

  @override
  Widget build(BuildContext context) => Panel(
        color: C.bg,
        radius: 12,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SectionLabel(title),
          const SizedBox(height: 6),
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(flex: 5, child: Text(r.label, style: ts(12, color: C.mute))),
                const SizedBox(width: 8),
                Expanded(flex: 6, child: Text(r.value, textAlign: TextAlign.right, style: ts(12, color: r.color ?? C.text))),
              ]),
            ),
        ]),
      );
}
