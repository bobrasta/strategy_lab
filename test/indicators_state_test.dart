import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strategy_lab/data/candle_cache.dart';
import 'package:strategy_lab/indicators/indicators_state.dart';
import 'package:strategy_lab/state/lab_state.dart';
import 'package:strategy_lab/state/settings.dart';

import 'support.dart';

void main() {
  test('an engine without indicator methods: a clear message, nothing started, the rest works', () async {
    final m = M7Engine(supported: false);
    final lab = await testLab(engine: m.engine);
    await lab.indicators.refresh();
    expect(lab.indicators.unsupported, IndicatorsState.kUnsupported);
    expect(lab.indicators.unsupported, contains('no indicator support'));
    lab.indicators.add('band', const {}); // e.g. restored from the settings
    await openFakeRun(writeFakeRun(), into: lab.chart);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(m.engine.callsOf('start_indicator'), isEmpty);
    expect(lab.indicators.instances.single.state, 'idle');
    await lab.refreshStrategies();
    expect(lab.chart.run, isNotNull);
    // A Build answered with "unknown method" also lands on the message, not an error banner.
    await lab.buildIndicator('band');
    expect(lab.chart.error, isNull);
    expect(lab.build, isNull);
  });

  test('add → start_indicator on the chart\'s data file → progress → output on the chart; edit; remove', () async {
    final m = M7Engine();
    final lab = await testLab(engine: m.engine);
    final ind = lab.indicators;
    await ind.refresh();
    expect(ind.list.map((x) => (x.name, x.status)), [('band', 'built'), ('fvg', 'stale'), ('donchian', 'not_built')]);
    await openFakeRun(writeFakeRun(), into: lab.chart);

    await ind.openEditor('band');
    expect(ind.schemaOf('band')!.inputs.map((i) => i.name), ['Tf', 'Period', 'Width']);
    final period = ind.schemaOf('band')!.inputs[1];
    ind.setDraft(period, '0');
    expect(ind.draftProblems(), ['Period: At least 1.']);
    ind.applyDraft();
    expect(ind.instances, isEmpty, reason: 'an invalid form is not applied');
    ind.setDraft(period, '7');
    ind.applyDraft();
    final i = ind.instances.single;
    expect(i.label, 'band (7)');
    await until(() => m.engine.callsOf('start_indicator').isNotEmpty);
    final call = m.engine.callsOf('start_indicator').single;
    expect(call['indicator'], 'band');
    expect(call['data'], lab.chart.candlesPath);
    expect(call['inputs'], {'Period': '7'}, reason: 'only non-default inputs, as runs');
    expect(call.containsKey('from'), isFalse, reason: 'the whole data file');
    await until(() => i.jobId != null);
    m.engine.emit({'event': 'indicator_queued', 'job_id': 'job-1', 'position': 1});
    await until(() => i.state == 'queued');
    m.engine.emit({'event': 'indicator_progress', 'job_id': 'job-1', 'pct': 42.5, 'sim_time': '2022-03-01 00:42:00'});
    await until(() => i.state == 'running');
    expect(i.status, 'Computing 42.5 % · 2022-03-01 00:42:00');
    expect(i.layer.isOn(lab.chart), isFalse, reason: 'nothing to draw yet');
    m.finish('job-1');
    await until(() => i.state == 'ok', what: 'the output to load');
    expect(i.output!.plotRecords, 133);
    expect(i.status, '133 plot values · 4 objects');
    expect(lab.chart.indicatorLayers.single, same(i.layer));
    expect(i.layer.isOn(lab.chart), isTrue);
    expect(lab.settings.indicators.single.toJson(), {'name': 'band', 'inputs': {'Period': '7'}, 'visible': true});

    // Edit inputs: recomputes (a cache hit answers at once).
    await ind.openEditor('band', instance: i);
    expect(ind.draft!.value(period), '7');
    ind.setDraft(ind.schemaOf('band')!.inputs[2], '0.25');
    m.cached = true;
    m.onStart = (job) => m.finish(job, cached: true); // finished arrives before the response is handled
    ind.applyDraft();
    expect(i.label, 'band (7, 0.25)');
    await until(() => i.state == 'ok' && m.engine.callsOf('start_indicator').length == 2);
    expect(m.engine.callsOf('start_indicator').last['inputs'], {'Period': '7', 'Width': '0.25'});
    expect(i.cached, isTrue);
    expect(i.status, endsWith('· cached'));

    // Visibility and removal.
    ind.setVisible(i, false);
    expect(i.layer.isOn(lab.chart), isFalse);
    expect(lab.settings.indicators.single.visible, isFalse);
    ind.remove(i);
    expect(lab.chart.indicatorLayers, isEmpty);
    expect(lab.settings.indicators, isEmpty);
  });

  test('the same indicator twice: two layers, one parsed output (a cache hit, same folder)', () async {
    final m = M7Engine()..onStart = null;
    final lab = await testLab(engine: m.engine);
    await openFakeRun(writeFakeRun(), into: lab.chart);
    m.onStart = (job) => m.finish(job, cached: job != 'job-1');
    final a = lab.indicators.add('band', const {}), b = lab.indicators.add('band', const {});
    await until(() => a.state == 'ok' && b.state == 'ok');
    expect(a.output, same(b.output));
    expect([a.cached, b.cached], [false, true]);
    expect(lab.chart.indicatorLayers, [a.layer, b.layer]);
    expect(a.layer.id, isNot(b.layer.id));
  });

  test('a failed indicator shows the error with the journal and stderr tails; Retry starts it again', () async {
    final m = M7Engine();
    final lab = await testLab(engine: m.engine);
    await openFakeRun(writeFakeRun(), into: lab.chart);
    m.onStart = (job) => m.finish(job, status: 'failed', extra: {
          'error': 'OnInit failed',
          'signal': 'SIGSEGV',
          'journal_tail': ['[2022-03-01 00:00:00] bad input'],
          'stderr_tail': ['segfault'],
        });
    final i = lab.indicators.add('band', const {});
    await until(() => i.state == 'failed');
    expect(i.status, 'Failed: OnInit failed · SIGSEGV');
    expect(i.journalTail, ['[2022-03-01 00:00:00] bad input']);
    expect(i.stderrTail, ['segfault']);
    expect(i.layer.isOn(lab.chart), isFalse);
    m.onStart = (job) => m.finish(job);
    lab.indicators.recompute(i);
    await until(() => i.state == 'ok');
  });

  test('removing a running indicator stops its job; a late finish is ignored', () async {
    final m = M7Engine();
    final lab = await testLab(engine: m.engine);
    await openFakeRun(writeFakeRun(), into: lab.chart);
    final i = lab.indicators.add('band', const {});
    await until(() => i.jobId == 'job-1');
    lab.indicators.remove(i);
    await until(() => m.engine.callsOf('stop_indicator').isNotEmpty);
    expect(m.engine.callsOf('stop_indicator').single, {'job_id': 'job-1'});
    m.finish('job-1');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(i.output, isNull);
    expect(lab.chart.indicatorLayers, isEmpty);
  });

  test('attached indicators are restored from the settings and recomputed when a chart opens and when its data file changes', () async {
    final m = M7Engine()..onStart = null;
    final f = File('${tempDir().path}/settings.json');
    final st = await Settings.load(f);
    st.indicators = [IndicatorSetting('band', const {}), IndicatorSetting('band', const {'Period': '9'}, visible: false)];
    await st.flush();
    final lab = await testLab(engine: m.engine, settings: await Settings.load(f));
    final ind = lab.indicators;
    expect(ind.instances.map((i) => (i.label, i.visible)), [('band', true), ('band (9)', false)]);
    expect(m.engine.callsOf('start_indicator'), isEmpty, reason: 'no chart yet');
    m.onStart = (job) => m.finish(job, cached: true);
    await openFakeRun(writeFakeRun(), into: lab.chart);
    await until(() => ind.instances.every((i) => i.state == 'ok'));
    final first = lab.chart.candlesPath!;
    expect(m.engine.callsOf('start_indicator').map((c) => c['data']), [first, first]);
    expect(m.engine.callsOf('start_indicator').map((c) => c['inputs']), [{}, {'Period': '9'}]);

    // Another data file on the chart: the old outputs go, both recompute on the new file.
    final other = writeTemp('other_m1.csv', candlesCsv(60, minutes: 1));
    await lab.chart.showData(runSeries(other, null, null), other);
    expect(ind.instances.every((i) => i.output == null || i.dataFile == other), isTrue);
    await until(() => ind.instances.every((i) => i.state == 'ok') && m.engine.callsOf('start_indicator').length == 4);
    expect(m.engine.callsOf('start_indicator').skip(2).map((c) => c['data']), [other, other]);
    expect(ind.instances.every((i) => i.dataFile == other), isTrue);
  });

  test('Build of an indicator streams into the Build tab; success refreshes the list and recomputes its instances', () async {
    final m = M7Engine();
    final lab = await testLab(engine: m.engine);
    await openFakeRun(writeFakeRun(), into: lab.chart);
    m.onStart = (job) => m.finish(job);
    final i = lab.indicators.add('fvg', const {});
    await until(() => i.state == 'ok');
    await lab.buildIndicator('fvg');
    expect(m.engine.callsOf('build_indicator').single, {'name': 'fvg'});
    expect(lab.build!.kind, 'indicator');
    expect(lab.chart.tab.name, 'build');
    m.engine.emit({'event': 'build_output', 'build_id': 'build-1', 'kind': 'indicator', 'stream': 'stderr', 'line': 'fvg.cpp:3: warning: unused'});
    m.status = const {'band': 'built', 'fvg': 'built', 'donchian': 'not_built'};
    m.engine.emit({'event': 'build_finished', 'build_id': 'build-1', 'kind': 'indicator', 'ok': true, 'seconds': 2.5, 'so': '/x/build/indicators/fvg.so'});
    await until(() => m.engine.callsOf('start_indicator').length == 2 && i.state == 'ok');
    expect(lab.build!.lines, ['fvg.cpp:3: warning: unused']);
    expect(lab.build!.status, 'ok');
    expect(lab.indicators.infoOf('fvg')!.status, 'built');
    expect(m.engine.callsOf('list_strategies'), isEmpty, reason: 'an indicator build does not touch the strategy list');
  });

  test('the engine stopping fails running indicators instead of leaving them spinning', () async {
    final m = M7Engine();
    final lab = await testLab(engine: m.engine);
    await openFakeRun(writeFakeRun(), into: lab.chart);
    final i = lab.indicators.add('band', const {});
    await until(() => i.jobId != null);
    m.engine.emit({'event': 'engine_exited', 'code': -9});
    await until(() => i.state == 'failed');
    expect(i.status, 'Failed: The engine stopped.');
    expect(lab, isA<LabState>());
  });
}
