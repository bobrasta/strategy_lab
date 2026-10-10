import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strategy_lab/run/history.dart';
import 'package:strategy_lab/run/protection.dart';
import 'package:strategy_lab/run/run_data.dart';

import 'support.dart';

int d(String s) => DateTime.parse('${s}T00:00:00Z').millisecondsSinceEpoch;

/// A fake run of [key] whose simulated span is [from]..[to] (its run.json range edited).
RunManifest runOver(String key, String from, String to, {Directory? dir}) {
  final run = writeFakeRun(strategyKey: key, from: from, to: to, dir: dir);
  final f = File('${run.path}/run.json');
  final j = jsonDecode(f.readAsStringSync()) as Map;
  (j['range'] as Map)['first_simulated_bar'] = '$from 00:00:00';
  (j['range'] as Map)['last_simulated_bar'] = '$to 23:59:00';
  f.writeAsStringSync(jsonEncode(j));
  return readManifest(run.path);
}

void main() {
  test('overlap: inclusive dates, open-ended end, unbounded run sides', () {
    const p = ProtectedPeriod('2024-01-01');
    expect(p.overlaps(d('2021-01-01'), d('2023-12-31') + 86399000), isFalse, reason: '2021–2023 ends before 2024');
    expect(p.overlaps(d('2023-06-01'), d('2024-01-01')), isTrue, reason: 'touches the first protected day');
    expect(p.overlaps(d('2025-01-01'), null), isTrue);
    expect(p.overlaps(null, null), isTrue, reason: 'an unbounded run always overlaps');
    const q = ProtectedPeriod('2024-01-01', '2024-06-30');
    expect(q.overlaps(d('2024-07-01'), d('2025-01-01')), isFalse, reason: 'starts the day after it ends');
    expect(q.overlaps(d('2024-06-30') + 3600000, d('2025-01-01')), isTrue);
    expect(q.overlaps(d('2021-01-01'), d('2023-12-31')), isFalse);
  });

  test('fvg_continuation: 2021–2023 runs are visible; runs into 2024 are hidden until confirmed for that period', () async {
    final lab = await testLab();
    final ok = runOver('fvg_continuation', '2021-01-01', '2023-12-31');
    final into = runOver('fvg_continuation', '2021-01-01', '2024-03-31');
    final other = runOver('ma_cross', '2021-01-01', '2026-10-07');
    expect(lab.isVisible(ok), isTrue);
    expect(lab.isVisible(into), isFalse);
    expect(lab.isVisible(other), isTrue, reason: 'no protection for ma_cross');

    final revealed = await lab.revealRun(into);
    expect(revealed, isNotNull);
    expect(lab.isVisible(revealed!), isTrue);
    final logged = jsonDecode(File('${into.dir}/$kConfirmationFile').readAsStringSync()) as Map;
    expect(logged['kind'], 'reveal');
    expect(logged['protected_period'], {'from': '2024-01-01', 'to': null});
    expect(DateTime.parse(logged['confirmed_at'] as String).isUtc, isTrue);
    expect(DateTime.now().toUtc().difference(DateTime.parse(logged['confirmed_at'] as String)).inSeconds, lessThan(60));
    expect(lab.isVisible(readManifest(into.dir)), isTrue, reason: 'the confirmation is read back from the folder');

    // A changed period needs a new confirmation.
    lab.setProtection('fvg_continuation', const ProtectedPeriod('2023-06-01'));
    expect(lab.isVisible(readManifest(into.dir)), isFalse);
    expect(lab.isVisible(ok), isFalse);
    lab.setProtection('fvg_continuation', null);
    expect(lab.isVisible(readManifest(into.dir)), isTrue);
  });

  test('protectedOverlap follows the tester dates (empty = data start/end)', () async {
    final lab = await testLab();
    lab.settings.lastStrategy = 'fvg_continuation';
    lab.settings
      ..from = '2021-01-01'
      ..to = '2023-12-31';
    expect(lab.protectedOverlap(), isNull);
    lab.settings.to = '2024-01-01';
    expect(lab.protectedOverlap(), const ProtectedPeriod('2024-01-01'));
    lab.settings.to = '';
    expect(lab.protectedOverlap(), isNotNull, reason: 'to data end');
    lab.settings.lastStrategy = 'ma_cross';
    expect(lab.protectedOverlap(), isNull);
  });

  test('startRun refuses an overlapping run without the confirmation (no engine call)', () async {
    final lab = await testLab();
    lab.settings
      ..lastStrategy = 'fvg_continuation'
      ..to = '';
    await lab.startRun();
    expect(lab.progress, isNull);
    expect(lab.chart.error, isNotNull);
  });

  test('history lists every run; openRun refuses a protected one and opens a confirmed one', () async {
    final root = tempDir();
    final runs = Directory('${root.path}/runs')..createSync();
    RunManifest mk(String name, String key, String from, String to) {
      final m = runOver(key, from, to, dir: Directory('${root.path}/$name')..createSync());
      final dest = '${runs.path}/$name';
      Directory(m.dir).renameSync(dest);
      return readManifest(dest);
    }

    final hidden = mk('a', 'fvg_continuation', '2021-01-01', '2024-12-31');
    mk('b', 'fvg_continuation', '2021-01-01', '2023-12-31');
    final h = await scanRuns(runs.path);
    expect(h, hasLength(2));
    final lab = await testLab();
    lab.history = h;
    expect(await lab.openRun(hidden), isFalse);
    expect(lab.chart.run, isNull);
    expect(lab.chart.error, contains('protected period'));
    final r = await lab.revealRun(hidden);
    expect(await lab.openRun(r!), isTrue);
    expect(lab.chart.run!.manifest.dir, hidden.dir);
    // Re-protecting with a new period closes the open run.
    lab.setProtection('fvg_continuation', const ProtectedPeriod('2022-01-01'));
    expect(lab.chart.run, isNull);
  });

  test('writeConfirmation creates the run folder if the worker has not yet', () async {
    final dir = '${tempDir().path}/runs/x';
    final c = await writeConfirmation(dir, kind: 'start', strategy: 'fvg_continuation', period: const ProtectedPeriod('2024-01-01'), runFrom: '2021-01-01', runTo: null);
    expect(readConfirmation(dir)!.covers(const ProtectedPeriod('2024-01-01')), isTrue);
    expect(readConfirmation(dir)!.confirmedAt, c.confirmedAt);
    expect((jsonDecode(File('$dir/$kConfirmationFile').readAsStringSync()) as Map)['run_to'], isNull);
  });
}
