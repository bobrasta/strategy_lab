import 'package:flutter/material.dart';

import '../run/protection.dart';
import '../state/lab_state.dart';
import '../theme.dart';
import 'common.dart';
import 'dialogs.dart';
import 'fields.dart';

/// Starts a run from the Tester settings, asking first when it overlaps a protected period.
Future<void> startRunGuarded(BuildContext context, LabState lab) async {
  final problems = lab.startProblems();
  if (problems.isNotEmpty) {
    lab.chart.showError(problems.join(' '));
    return;
  }
  final p = lab.protectedOverlap();
  if (p != null) {
    final ok = await confirmProtectedRun(context, strategy: lab.strategy!, period: p, from: lab.settings.from, to: lab.settings.to);
    if (!ok) return;
  }
  await lab.startRun(confirmed: p);
}

Color statusColor(String status) => switch (status) { 'built' => C.green, 'stale' => C.gold, _ => C.mute };
String statusLabel(String status) => switch (status) { 'built' => 'built', 'stale' => 'stale: rebuild', _ => 'not built' };

/// MT5's Strategy Tester settings + inputs, as the right drawer.
class TesterPanel extends StatelessWidget {
  const TesterPanel({super.key, required this.lab});
  final LabState lab;

  @override
  Widget build(BuildContext context) {
    final s = lab.chart;
    return Panel(
      shadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 48, offset: Offset(-16, 0))],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 10, 6),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Strategy Tester', style: ts(15, w: FontWeight.w500)),
                const SizedBox(height: 2),
                Text('Runs go to ${lab.runsDir}', overflow: TextOverflow.ellipsis, style: ts(11, color: C.mute)),
              ]),
            ),
            RoundIconButton(icon: AppIcons.close, color: C.mute, tooltip: 'Close', onTap: () => s.toggleRight(false)),
          ]),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _StrategySection(lab: lab),
              const SizedBox(height: 18),
              _InputsSection(lab: lab),
              const SizedBox(height: 18),
              _DataSection(lab: lab),
              const SizedBox(height: 18),
              _ModelSection(lab: lab),
              const SizedBox(height: 18),
              _CostsSection(lab: lab),
            ]),
          ),
        ),
        _StartFooter(lab: lab),
      ]),
    );
  }
}

class _StrategySection extends StatelessWidget {
  const _StrategySection({required this.lab});
  final LabState lab;

  @override
  Widget build(BuildContext context) {
    final info = lab.strategyInfo, b = lab.build;
    final building = b != null && b.running && b.name == lab.strategy;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionLabel('Strategy'),
      const SizedBox(height: 8),
      if (lab.strategies.isEmpty)
        Text(lab.engine.ready ? 'No strategies in strategies/*.cpp.' : 'The strategy list comes from the engine, which is not ready.', style: ts(12, color: C.mute))
      else
        Row(children: [
          Expanded(
            child: PillMenu<String>(
              key: const ValueKey('strategy-menu'),
              values: [for (final x in lab.strategies) x.name],
              selected: info?.name ?? lab.strategies.first.name,
              onSelected: lab.selectStrategy,
              labelOf: (n) => n,
              leading: (n) {
                final st = lab.strategies.where((x) => x.name == n).firstOrNull?.status ?? '';
                return Container(width: 7, height: 7, decoration: BoxDecoration(color: statusColor(st), shape: BoxShape.circle));
              },
            ),
          ),
          const SizedBox(width: 8),
          PillButton(
            key: const ValueKey('build-strategy'),
            label: building ? 'Building…' : (info?.status == 'built' ? 'Rebuild' : 'Build'),
            icon: AppIcons.build,
            height: 30,
            fontSize: 12,
            color: info?.status == 'stale' || info?.status == 'not_built' ? C.gold : null,
            borderColor: info?.status == 'stale' || info?.status == 'not_built' ? C.gold : null,
            enabled: lab.engine.ready && info != null && !building,
            onTap: lab.buildStrategy,
          ),
        ]),
      if (info != null) ...[
        const SizedBox(height: 6),
        Row(children: [
          Text(statusLabel(info.status), style: ts(11, color: statusColor(info.status))),
          const SizedBox(width: 8),
          Expanded(child: Text(info.source, overflow: TextOverflow.ellipsis, style: ts(11, color: C.mute))),
        ]),
      ],
    ]);
  }
}

class _InputsSection extends StatelessWidget {
  const _InputsSection({required this.lab});
  final LabState lab;

  @override
  Widget build(BuildContext context) {
    final sc = lab.schema, name = lab.strategy;
    final err = name == null ? null : lab.schemaErrors[name];
    final changed = lab.settings.inputs[name]?.isNotEmpty ?? false;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const SectionLabel('Inputs'),
        const Spacer(),
        if (changed)
          HoverBox(onTap: lab.resetInputs, builder: (_, h) => Text('Reset to defaults', style: ts(11, color: h ? C.text : C.mute))),
      ]),
      const SizedBox(height: 6),
      if (err != null)
        Text(err, style: ts(12, color: C.red))
      else if (sc == null)
        Text(lab.strategyInfo?.runnable ?? false ? 'Reading inputs…' : 'Build the strategy to see its inputs.', style: ts(12, color: C.mute))
      else if (sc.isEmpty)
        Text('This strategy has no inputs.', style: ts(12, color: C.mute))
      else
        for (final i in sc) _InputRow(lab: lab, spec: i),
    ]);
  }
}

class _InputRow extends StatelessWidget {
  const _InputRow({required this.lab, required this.spec});
  final LabState lab;
  final InputSpec spec;

  @override
  Widget build(BuildContext context) {
    final v = lab.inputValue(spec), err = spec.check(v), isDefault = v == spec.def;
    final Widget control = switch (spec.type) {
      'bool' => PillSwitch(value: v == 'true', onChanged: (x) => lab.setInput(spec, '$x')),
      'timeframe' => PillMenu<String>(values: kStrategyTimeframes, selected: kStrategyTimeframes.contains(v) ? v : spec.def, onSelected: (x) => lab.setInput(spec, x), labelOf: (x) => x),
      'choice' => PillMenu<String>(values: spec.choices, selected: spec.choices.contains(v) ? v : spec.def, onSelected: (x) => lab.setInput(spec, x), labelOf: (x) => x),
      _ => PillField(value: v, hint: spec.def, width: 140, error: err != null, onChanged: (x) => lab.setInput(spec, x.trim().isEmpty ? spec.def : x.trim())),
    };
    final range = spec.min != null || spec.max != null ? ' · ${spec.min == null ? '' : _n(spec.min!)}–${spec.max == null ? '' : _n(spec.max!)}' : '';
    return FormRow(
      label: spec.name,
      labelWidth: 120,
      sub: err ?? '${spec.description}$range${isDefault ? '' : ' · default ${spec.def}'}',
      subColor: err != null ? C.red : (isDefault ? C.mute : C.gold),
      child: control,
    );
  }

  static String _n(double x) => x == x.truncateToDouble() ? x.toInt().toString() : '$x';
}

class _DataSection extends StatelessWidget {
  const _DataSection({required this.lab});
  final LabState lab;

  @override
  Widget build(BuildContext context) {
    final st = lab.settings, name = lab.strategy;
    final prot = name == null ? null : lab.protectionFor(name);
    final overlap = lab.protectedOverlap();
    bool bad(String v) => v.isNotEmpty && !isIsoDate(v);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionLabel('Data and dates'),
      const SizedBox(height: 6),
      FormRow(
        label: 'M1 data',
        sub: st.dataFile,
        child: Row(children: [
          Expanded(child: Text(baseNameOf(st.dataFile), overflow: TextOverflow.ellipsis, style: ts(12))),
          PillButton(label: 'Choose…', icon: AppIcons.folder, height: 28, fontSize: 12, onTap: lab.pickDataFile),
        ]),
      ),
      FormRow(
        label: 'From (UTC)',
        child: PillField(fieldKey: const ValueKey('from-field'), value: st.from, hint: 'data start', width: 140, error: bad(st.from), onChanged: (v) => lab.set((s) => s.from = v.trim())),
      ),
      FormRow(
        label: 'To (UTC)',
        sub: 'Inclusive. History before From is visible to the strategy, as in MT5.',
        child: PillField(fieldKey: const ValueKey('to-field'), value: st.to, hint: 'data end', width: 140, error: bad(st.to), onChanged: (v) => lab.set((s) => s.to = v.trim())),
      ),
      if (name != null)
        Container(
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          decoration: BoxDecoration(
            color: overlap != null ? C.gold.withOpacity(0.08) : C.bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: overlap != null ? C.gold.withOpacity(0.45) : C.line),
          ),
          child: Row(children: [
            Icon(prot == null ? AppIcons.unlock : AppIcons.lock, size: 15, color: overlap != null ? C.gold : C.mute),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                prot == null
                    ? 'No protected period for $name.'
                    : overlap != null
                        ? 'Protected: ${prot.label}. This range overlaps it, so Start asks you to confirm.'
                        : 'Protected: ${prot.label}.',
                style: ts(11.5, color: overlap != null ? C.gold : C.mute, height: 1.35),
              ),
            ),
            PillButton(
              label: 'Edit',
              height: 26,
              fontSize: 11,
              onTap: () async {
                final (changed, p) = await editProtection(context, name, prot);
                if (!changed || p == prot) return;
                final weaker = prot != null && (p == null || p.fromMs > prot.fromMs || (prot.to == null ? p.to != null : (p.to != null && p.to!.compareTo(prot.to!) < 0)));
                if (weaker && context.mounted && !await confirmUnprotect(context, name)) return;
                lab.setProtection(name, p);
              },
            ),
          ]),
        ),
    ]);
  }
}

String baseNameOf(String p) => p.split(RegExp(r'[\\/]')).last;

class _ModelSection extends StatelessWidget {
  const _ModelSection({required this.lab});
  final LabState lab;

  @override
  Widget build(BuildContext context) {
    final st = lab.settings;
    final acct = lab.profile;
    bool bad(String v) => v.isNotEmpty && (double.tryParse(v) ?? 0) <= 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionLabel('Model and account'),
      const SizedBox(height: 6),
      FormRow(
        label: 'Tick path',
        sub: st.tickPath == 'bull_bear' ? 'MT5 "1 minute OHLC"' : (st.tickPath == 'nearest' ? 'Nearer extreme first (default)' : 'Fixed order (stress test)'),
        child: PillMenu<String>(values: const ['nearest', 'bull_bear', 'olhc', 'ohlc'], selected: st.tickPath, onSelected: (v) => lab.set((s) => s.tickPath = v), labelOf: (v) => v),
      ),
      FormRow(
        label: 'Ambiguity',
        sub: st.ambiguity == 'path' ? 'Whichever level the path reaches first (MT5)' : (st.ambiguity == 'sl_first' ? 'Pessimistic: SL wins' : 'Optimistic: TP wins'),
        child: PillMenu<String>(values: const ['path', 'sl_first', 'tp_first'], selected: st.ambiguity, onSelected: (v) => lab.set((s) => s.ambiguity = v), labelOf: (v) => v),
      ),
      FormRow(label: 'Deposit (USD)', child: PillField(value: st.deposit, hint: '10000', width: 140, error: bad(st.deposit), onChanged: (v) => lab.set((s) => s.deposit = v.trim()))),
      FormRow(
        label: 'Leverage 1:',
        sub: acct.isEmpty ? null : 'Stop-out 50 % · margin call 100 % (MT5 tester defaults)',
        child: PillField(value: st.leverage, hint: '100', width: 140, error: bad(st.leverage), onChanged: (v) => lab.set((s) => s.leverage = v.trim())),
      ),
    ]);
  }
}

class _CostsSection extends StatelessWidget {
  const _CostsSection({required this.lab});
  final LabState lab;

  @override
  Widget build(BuildContext context) {
    final costs = (lab.profile['costs'] as Map?) ?? const {};
    final spread = costs['spread'], slip = costs['slippage'];
    final zero = lab.settings.costs['costs'] == 'none';
    String spreadHint() => spread is Map ? '${spread['default'] ?? ''} pts + sessions' : '$spread';
    String slipHint() => slip is Map ? '${slip['mode']}${slip['max_points'] != null ? ':${slip['max_points']}' : (slip['points'] != null ? ':${slip['points']}' : '')}' : '';
    Widget field(String opt, String label, String hint, String sub) => FormRow(
          label: label,
          sub: sub,
          child: PillField(value: lab.settings.costs[opt] ?? '', hint: hint, width: 140, onChanged: (v) => lab.setCost(opt, v)),
        );
    final overridden = lab.settings.costs.isNotEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const SectionLabel('Costs'),
        const Spacer(),
        if (overridden)
          HoverBox(
            onTap: () {
              for (final k in [...lab.settings.costs.keys]) {
                lab.setCost(k, '');
              }
            },
            builder: (_, h) => Text('Use the profile', style: ts(11, color: h ? C.text : C.mute)),
          ),
      ]),
      const SizedBox(height: 4),
      Text(lab.profileError ?? 'Empty fields use ${baseNameOf(lab.settings.profilePath)}. Every value is recorded in run.json.', style: ts(11, color: lab.profileError != null ? C.red : C.mute, height: 1.35)),
      const SizedBox(height: 4),
      FormRow(
        label: 'Zero-cost run',
        sub: zero ? 'No spread, commission, slippage or swap. The report flags it.' : null,
        subColor: C.gold,
        child: PillSwitch(value: zero, onChanged: (v) => lab.setCost('costs', v ? 'none' : '')),
      ),
      if (!zero) ...[
        field('spread', 'Spread (points)', spreadHint(), 'A number replaces the profile\'s spread with a constant.'),
        field('commission', 'Commission', '${costs['commission_per_lot_side'] ?? ''}', 'USD per lot per side'),
        field('slippage', 'Slippage', slipHint(), 'none, fixed:<pts>, random:<max pts>'),
        field('seed', 'Seed', '${slip is Map ? slip['seed'] ?? 1 : 1}', 'SplitMix64 seed for random slippage'),
        field('swap_mode', 'Swap mode', '${costs['swap_mode'] ?? ''}', 'money or interest_current'),
        field('swap_long', 'Swap long', '${costs['swap_long'] ?? ''}', ''),
        field('swap_short', 'Swap short', '${costs['swap_short'] ?? ''}', ''),
        field('triple_swap_day', 'Triple swap day', '${costs['triple_swap_day'] ?? ''}', ''),
      ],
    ]);
  }
}

class _StartFooter extends StatelessWidget {
  const _StartFooter({required this.lab});
  final LabState lab;

  @override
  Widget build(BuildContext context) {
    final p = lab.progress, active = p?.active ?? false;
    final problems = active ? const <String>[] : lab.startProblems();
    final String line;
    if (p == null) {
      line = problems.isEmpty ? 'Ready to start.' : problems.first;
    } else {
      line = switch (p.state) {
        'queued' => 'Queued…',
        'running' => p.stage == 'loading' ? 'Loading data…' : '${p.pct.toStringAsFixed(1)} % · ${p.simTime.isEmpty ? 'starting' : p.simTime}',
        'ok' => problems.isEmpty ? 'Last run finished · ready to start.' : problems.first,
        'stopped' => 'Last run stopped.',
        _ => 'Run failed: ${[p.error, if (p.signal != null) p.signal].whereType<String>().join(' · ')}',
      };
    }
    final failed = p?.state == 'failed';
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: C.line))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (active) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(value: p!.pct <= 0 ? null : p.pct / 100, minHeight: 4, backgroundColor: C.line, color: C.gold),
          ),
          const SizedBox(height: 8),
        ],
        Text(line, key: const ValueKey('run-status'), maxLines: 3, overflow: TextOverflow.ellipsis, style: ts(12, color: failed ? C.red : (problems.isNotEmpty && !active ? C.gold : C.mute), height: 1.35)),
        if (failed && (p!.journalTail.isNotEmpty || p.stderrTail.isNotEmpty)) ...[
          const SizedBox(height: 6),
          Container(
            constraints: const BoxConstraints(maxHeight: 110),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: C.bg, borderRadius: BorderRadius.circular(8), border: Border.all(color: C.line)),
            child: SingleChildScrollView(
              child: SelectableText([...p.stderrTail, ...p.journalTail].join('\n'), style: ts(10.5, color: C.mute, height: 1.3)),
            ),
          ),
        ],
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: PillButton(
              key: const ValueKey('start-run'),
              label: active ? 'Running…' : 'Start',
              icon: active ? null : AppIcons.play,
              variant: PillVariant.primary,
              height: 36,
              enabled: !active && problems.isEmpty,
              onTap: () => startRunGuarded(context, lab),
            ),
          ),
          const SizedBox(width: 8),
          PillButton(key: const ValueKey('stop-run'), label: 'Stop', icon: AppIcons.stop, height: 36, enabled: active, onTap: lab.stopRun),
        ]),
      ]),
    );
  }
}
