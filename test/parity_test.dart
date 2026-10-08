// Parity with the Python study. Reads the real outputs from FXDATA_DIR
// (default /home/bob/Documents/fxdata) and skips with a message if they're missing.
import 'dart:convert';
import 'dart:io';

import 'package:backy/data/conditions_summary.dart';
import 'package:backy/data/events.dart';
import 'package:backy/data/stats.dart';
import 'package:backy/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _files = ['fvg_events.csv', 'fvg_events_app.csv', 'fvg_fake_events.csv', 'fvg_control_events.csv', 'fvg_conditions_summary.json'];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final skip = skipUnlessFxdata(_files);

  late AppState s;
  setUpAll(() async {
    if (skip != null) return;
    s = AppState();
    await s.loadEvents(fx('fvg_events.csv')); // the app picks up fvg_events_app.csv + companions
  });

  test('no filters: 18,359 first touches, bounce rate 0.579, P(bounce | d=0.5) 0.481', () {
    expect(s.error, isNull);
    expect(s.eventsPath, endsWith('fvg_events_app.csv'));
    expect(s.stats.total, 18359);
    expect(s.stats.bounceRate!.toStringAsFixed(3), '0.579');
    expect(s.stats.curve[5]!.toStringAsFixed(3), '0.481');
  }, skip: skip);

  test('same numbers from plain fvg_events.csv (fallback without condition columns)', () {
    final plain = AppState();
    return plain.loadEvents(writeTemp('fvg_events.csv', File(fx('fvg_events.csv')).readAsStringSync())).then((_) {
      expect(plain.stats.total, 18359);
      expect(plain.stats.bounceRate!.toStringAsFixed(3), '0.579');
      expect(plain.stats.curve[5]!.toStringAsFixed(3), '0.481');
      expect(plain.filterAvailable('Displacement'), isFalse);
    });
  }, skip: skip);

  test('in-sample Asia formation: app diff matches fvg_conditions_summary.json (+3.4pp)', () {
    final j = jsonDecode(File(fx('fvg_conditions_summary.json')).readAsStringSync()) as Map<String, dynamic>;
    final row = (j['periods']['in'] as List).cast<Map>().firstWhere((r) => r['feature'] == 'form_session' && r['bucket'] == 'Asia');

    s.applyFilterPreset('Asia formation (candidate)');
    s.setFilter('Period', 1); // In-sample 2021–23
    final c = s.comparison;
    expect(c.real.resolved, row['n_real']);
    expect(c.fake!.resolved, row['n_fake']);
    expect(c.realMinusFakePp!, closeTo((row['diff_pp'] as num).toDouble(), 1e-9));
    expect(c.realMinusFakePp!.toStringAsFixed(1), '3.4');
    expect(c.zRealFake!, closeTo((row['z'] as num).toDouble(), 1e-9));
    expect(c.controlDiffPp!, closeTo((row['control_diff_pp'] as num).toDouble(), 1e-9));
    expect(verdictCode(c.verdict), row['verdict']);
    expect(c.verdict, Verdict.candidate);
    s.clearFilters();
  }, skip: skip);

  test('every bucket and period in the JSON matches the app', () async {
    final sum = (await ConditionsSummary.loadNextTo(fx('fvg_events.csv')))!;
    expect(sum.rows.length, greaterThan(40));
    expect(crossCheck(sum, s.events, s.fakeEvents, s.controlEvents), isEmpty);
    expect(s.notice ?? '', isNot(contains("don't match")));
  }, skip: skip);

  test('hold-out is locked by default and nothing is 2026 yet', () {
    expect(s.holdoutLocked, isTrue);
    expect(s.events.where((e) => e.period == Period.holdout), isEmpty);
  }, skip: skip);
}
