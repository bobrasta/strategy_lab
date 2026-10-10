import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strategy_lab/run/protection.dart';
import 'package:strategy_lab/state/settings.dart';

import 'support.dart';

void main() {
  test('everything round-trips through settings.json', () async {
    final f = File('${tempDir().path}/sub/settings.json');
    final s = await Settings.load(f);
    expect(s.dataFile, kDefaultDataFile);
    s
      ..lastStrategy = 'ma_cross'
      ..from = '2021-01-01'
      ..to = '2023-12-31'
      ..dataFile = '/data/m1.csv'
      ..tickPath = 'bull_bear'
      ..ambiguity = 'sl_first'
      ..deposit = '5000'
      ..leverage = '30'
      ..lastRunDir = '/runs/x';
    s.inputs['ma_cross'] = {'FastPeriod': '10'};
    s.costs['spread'] = '150';
    s.protectedPeriods['ma_cross'] = const ProtectedPeriod('2025-01-01', '2025-06-30');
    s.protectedPeriods['fvg_continuation'] = null; // removed by the user
    await s.flush();
    final r = await Settings.load(f);
    expect([r.lastStrategy, r.from, r.to, r.dataFile, r.tickPath, r.ambiguity, r.deposit, r.leverage, r.lastRunDir],
        ['ma_cross', '2021-01-01', '2023-12-31', '/data/m1.csv', 'bull_bear', 'sl_first', '5000', '30', '/runs/x']);
    expect(r.inputs['ma_cross'], {'FastPeriod': '10'});
    expect(r.costs, {'spread': '150'});
    expect(r.protectionFor('ma_cross'), const ProtectedPeriod('2025-01-01', '2025-06-30'));
    expect(r.protectionFor('fvg_continuation'), isNull, reason: 'a removed default stays removed');
  });

  test('defaults: fvg_continuation is protected from 2024-01-01; a damaged file falls back to defaults', () async {
    final f = File(writeTemp('settings.json', '{not json'));
    final s = await Settings.load(f);
    expect(s.protectionFor('fvg_continuation'), const ProtectedPeriod('2024-01-01'));
    expect(s.protectionFor('ma_cross'), isNull);
    expect(s.binary, '$kDefaultEngineRepo/build/release/hummer');
  });

  test('changed() coalesces saves', () async {
    final f = File('${tempDir().path}/settings.json');
    final s = await Settings.load(f);
    for (var i = 0; i < 20; i++) {
      s.from = '2021-01-${(i + 1).toString().padLeft(2, '0')}';
      s.changed();
    }
    expect(f.existsSync(), isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 450));
    expect((await Settings.load(f)).from, '2021-01-20');
  });
}
