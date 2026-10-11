// Second process of the M7 acceptance: same settings folder as indicators_test.dart. The data chart and
// the attached indicator (donchian, Period 25) come back after the restart, and the engine serves it
// from its cache (the folder computed in the first process; no worker).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:strategy_lab/main.dart';

const settingsDir = String.fromEnvironment('SETTINGS_DIR');

Future<void> waitFor(WidgetTester t, bool Function() ok, String what, {Duration limit = const Duration(minutes: 2)}) async {
  final sw = Stopwatch()..start();
  while (!ok()) {
    if (sw.elapsed > limit) fail('timed out waiting for $what');
    await t.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('after a restart: attached indicators restored and served from the cache', (t) async {
    final out = File('$settingsDir/indicators_out.txt').readAsStringSync().trim();
    final lab = await createLab(settingsDir: settingsDir);
    final s = lab.chart, ind = lab.indicators;
    final saved = lab.settings.indicators.single;
    expect([saved.name, saved.visible], ['donchian', true]);
    expect(saved.inputs, {'Period': '25'});
    expect(lab.settings.chartDataFile, lab.settings.dataFile);
    await t.pumpWidget(StrategyLabApp(lab: lab));
    await lab.init();
    await waitFor(t, () => s.loaded && s.candlesPath == lab.settings.dataFile, 'data chart restored');
    final i = ind.instances.single;
    await waitFor(t, () => i.state == 'ok' && i.output != null, 'donchian restored (${i.status})');
    expect(i.cached, isTrue, reason: 'served from the engine cache');
    expect(i.out, out);
    expect(i.label, 'donchian (25)');
    expect(s.indicatorLayers, contains(i.layer));
    await t.pumpAndSettle();
    await lab.shutdown();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect('${(await Process.run('pgrep', ['-a', 'hummer'])).stdout}'.trim(), isEmpty);
  }, timeout: const Timeout(Duration(minutes: 6)));
}
