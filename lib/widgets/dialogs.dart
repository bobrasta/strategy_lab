import 'package:flutter/material.dart';

import '../run/protection.dart';
import '../run/run_data.dart';
import '../theme.dart';
import '../util/format.dart';
import 'common.dart';
import 'fields.dart';

Widget _body(String text) => SizedBox(width: 440, child: Text(text, style: ts(13, color: C.mute, height: 1.45)));

/// Asked before starting a run that overlaps a strategy's protected period.
Future<bool> confirmProtectedRun(BuildContext context, {required String strategy, required ProtectedPeriod period, required String from, required String to}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      key: const ValueKey('protected-run-dialog'),
      title: Row(children: [
        const Icon(AppIcons.lock, size: 18, color: C.gold),
        const SizedBox(width: 8),
        Expanded(child: Text('Run into the protected period?', style: ts(16, w: FontWeight.w500))),
      ]),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        _body('$strategy has a protected period: ${period.label}. '
            'This run (${from.isEmpty ? 'data start' : from} to ${to.isEmpty ? 'data end' : to}) overlaps it, so its results would include data you are holding out.'),
        const SizedBox(height: 10),
        _body('If you continue, the confirmation is logged with a timestamp in the run\'s folder ($kConfirmationFile), and this run\'s results are shown.'),
      ]),
      actions: [
        PillButton(key: const ValueKey('protected-cancel'), label: 'Cancel', onTap: () => Navigator.pop(ctx, false)),
        PillButton(
          key: const ValueKey('protected-confirm'),
          label: 'Run including ${period.label}',
          color: C.gold,
          borderColor: C.gold,
          onTap: () => Navigator.pop(ctx, true),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// Asked before showing an existing run whose span overlaps a protected period it wasn't confirmed for.
Future<bool> confirmReveal(BuildContext context, RunManifest m, ProtectedPeriod period) async {
  final span = m.simSpan;
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Row(children: [
        const Icon(AppIcons.lock, size: 18, color: C.gold),
        const SizedBox(width: 8),
        Expanded(child: Text('Show a protected run?', style: ts(16, w: FontWeight.w500))),
      ]),
      content: _body('${m.runId} covers ${span == null ? 'an unknown span' : '${fmtDate(span.$1)} to ${fmtDate(span.$2)}'}, which overlaps '
          "${m.strategyKey}'s protected period (${period.label}). It wasn't confirmed for that period, so its results are hidden.\n\n"
          'Showing it logs the confirmation with a timestamp in its folder ($kConfirmationFile).'),
      actions: [
        PillButton(label: 'Keep hidden', onTap: () => Navigator.pop(ctx, false)),
        PillButton(label: 'Show results', color: C.gold, borderColor: C.gold, onTap: () => Navigator.pop(ctx, true)),
      ],
    ),
  );
  return r ?? false;
}

/// Edits a strategy's protected period. Returns (changed, period); a null period removes it.
Future<(bool, ProtectedPeriod?)> editProtection(BuildContext context, String strategy, ProtectedPeriod? current) async {
  var from = current?.from ?? '', to = current?.to ?? '';
  final r = await showDialog<(bool, ProtectedPeriod?)>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
      final fromOk = isIsoDate(from), toOk = to.isEmpty || isIsoDate(to);
      final order = !fromOk || to.isEmpty || !isIsoDate(to) || from.compareTo(to) <= 0;
      return AlertDialog(
        title: Text('Protected period · $strategy', style: ts(16, w: FontWeight.w500)),
        content: SizedBox(
          width: 440,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Runs that overlap these dates need a confirmation before they start, and their results stay hidden in summaries and run history unless the run was confirmed.',
                style: ts(13, color: C.mute, height: 1.45)),
            const SizedBox(height: 14),
            FormRow(label: 'From', child: PillField(value: from, hint: 'YYYY-MM-DD', width: 150, error: from.isNotEmpty && !fromOk, onChanged: (v) => setS(() => from = v.trim()))),
            FormRow(
              label: 'To',
              sub: 'Leave empty for no end.',
              child: PillField(value: to, hint: 'open-ended', width: 150, error: !toOk || !order, onChanged: (v) => setS(() => to = v.trim())),
            ),
          ]),
        ),
        actions: [
          if (current != null) PillButton(label: 'Remove protection', color: C.red, borderColor: C.red, onTap: () => Navigator.pop(ctx, (true, null))),
          PillButton(label: 'Cancel', onTap: () => Navigator.pop(ctx, (false, current))),
          PillButton(
            label: 'Save',
            variant: PillVariant.primary,
            enabled: fromOk && toOk && order,
            onTap: () => Navigator.pop(ctx, (true, ProtectedPeriod(from, to.isEmpty ? null : to))),
          ),
        ],
      );
    }),
  );
  return r ?? (false, current);
}

/// Removing or narrowing a protection is a deliberate act: asked once more.
Future<bool> confirmUnprotect(BuildContext context, String strategy) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Remove $strategy\'s protection?', style: ts(16, w: FontWeight.w500)),
      content: _body('Runs over those dates will start without asking, and results already on disk that overlap it become visible.'),
      actions: [
        PillButton(label: 'Keep it', onTap: () => Navigator.pop(ctx, false)),
        PillButton(label: 'Remove', color: C.red, borderColor: C.red, onTap: () => Navigator.pop(ctx, true)),
      ],
    ),
  );
  return r ?? false;
}
