import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strategy_lab/run/run_data.dart';

import 'support.dart';

void main() {
  test('loads every file of a run folder', () {
    final d = loadRunFiles(writeFakeRun().path);
    expect(d.manifest.strategyKey, 'fake');
    expect(d.manifest.inputs, {'Lots': '0.1'});
    expect(d.manifest.simSpan, (at(0), at(119, 59)));
    expect(d.trades.map((t) => t.ticket), [1, 3]);
    expect(d.trades.first.closeMs, at(40, 20));
    expect(d.deals, hasLength(4));
    expect(d.deals.first.cells.last, 'a, quoted', reason: 'quoted CSV field with a comma');
    expect(d.deals.first.ms, at(10));
    expect(d.drawings.map((e) => e.op), ['create', 'create', 'create', 'move', 'delete']);
    expect(d.journal.map((j) => j.ms), [at(10), at(65)]);
    expect(d.journal.first.text, 'market buy 0.10 XAUUSD -> deal #1');
  });

  test('a folder without run.json (stopped run) is a clear error', () {
    expect(() => loadRunFiles(tempDir().path), throwsA(isA<RunLoadError>().having((e) => e.message, 'm', contains('No run.json'))));
  });

  test('app = CLI: a real engine run reads back with the same trades and deals as its CSV files', () async {
    final out = '${tempDir().path}/ma';
    final r = await Process.run(engineBinary, [
      'run', '--data', fx('xauusd_m1_2021-01-04_2021-01-11.csv'), '--strategy', 'ma_cross', '--set', 'Tf=M5', '--equity-tf', 'M1', '--out', out,
    ], workingDirectory: engineRepo);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    final d = loadRunFiles(out);
    final csv = File('$out/trades.csv').readAsLinesSync();
    final head = csv.first.split(',');
    expect(d.trades.length, csv.length - 1);
    expect(d.trades.length, greaterThan(5));
    for (var i = 0; i < d.trades.length; i++) {
      final row = csv[i + 1].split(',');
      final t = d.trades[i];
      expect(t.ticket, int.parse(row[head.indexOf('ticket')]));
      expect(t.openTime, row[head.indexOf('open_time')]);
      expect(t.closeTime, row[head.indexOf('close_time')]);
      expect(t.net, double.parse(row[head.indexOf('net')]), reason: 'bit-identical net of #${t.ticket}');
      expect(t.openPrice, double.parse(row[head.indexOf('open_price')]));
    }
    expect(d.deals.length, File('$out/deals.csv').readAsLinesSync().length - 1);
    expect(d.manifest.ok, isTrue);
    expect(d.manifest.netProfit, isNotNull);
  }, skip: skipUnlessEngine() ?? skipUnlessFxdata(['xauusd_m1_2021-01-04_2021-01-11.csv']), timeout: const Timeout(Duration(minutes: 2)));
}
