// Practice sessions (M8) against a fake `hummer serve`: the chart opens in replay before the start date
// and stays there, advances follow the cursor (coalesced, never ahead of it), orders only at the newest
// point reached, and a protected period is entered only after a logged confirmation.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strategy_lab/practice/practice_state.dart';
import 'package:strategy_lab/run/protection.dart';
import 'package:strategy_lab/state/lab_state.dart';
import 'package:strategy_lab/state/settings.dart';

import 'support.dart';

class _Fake {
  _Fake() {
    engine = FakeEngine(_handle);
  }
  late final FakeEngine engine;
  final advances = <String>[];
  final requests = <(String, Map)>[];
  Completer<void>? hold; // when set, advances wait for it

  Map<String, dynamic> state(String? time) => {
        'time': time,
        'balance': 10000,
        'equity': 10000,
        'margin': 0,
        'free_margin': 10000,
        'margin_level': 0,
        'profit': 0,
        'position': null,
        'orders': [],
        'trades_total': 0,
        'trades': [],
        'journal': [],
      };

  Future<dynamic> _handle(String m, Map<String, dynamic> p) async {
    if (m == 'start_session') {
      Future<void>.delayed(const Duration(milliseconds: 5), () {
        engine.emit({'event': 'session_ready', 'session_id': 's1', 'out': p['out'], 'resumed_requests': 0, 'state': state(null)});
      });
      return {'session_id': 's1', 'out': p['out']};
    }
    if (m == 'session_call') {
      final method = '${p['method']}', params = p['params'] as Map;
      if (method == 'advance') {
        advances.add('${params['to']}');
        if (hold != null) await hold!.future;
        return state('${params['to']}');
      }
      requests.add((method, params));
      return {'request': {'retcode': 10009, 'comment': 'done'}, 'state': state(advances.isEmpty ? null : advances.last)};
    }
    if (m == 'stop_session') return {};
    throw StateError('unexpected $m');
  }
}

/// 40 M15 bars from 2021-12-31 20:00 UTC to 2022-01-01 05:45 (over the 2022-01-01 boundary).
Future<(LabState, _Fake, Directory)> _lab({ProtectedPeriod? protect}) async {
  final dir = tempDir();
  final data = writeTemp('m15.csv', candlesCsv(40, start: DateTime.utc(2021, 12, 31, 20)), dir: dir);
  final st = await Settings.load(File('${dir.path}/settings.json'));
  st
    ..engineRepo = dir.path
    ..dataFile = data;
  if (protect != null) st.protectedPeriods[kPracticeKey] = protect;
  final f = _Fake();
  final lab = await testLab(engine: f.engine, settings: st);
  return (lab, f, dir);
}

Future<void> _idle(PracticeState p) => until(() => !p.busy, what: 'idle');

void main() {
  test('start: replay just before the start date, Explore refused, trading after the first step', () async {
    final (lab, f, _) = await _lab();
    final s = lab.chart, p = lab.practice;
    var sawFullChart = false;
    s.addListener(() {
      if (s.loaded && (!s.isReplay || s.selectMode)) sawFullChart = true;
    });
    await p.start(data: lab.settings.dataFile, startDate: '2022-01-01');
    await _idle(p);
    expect(sawFullChart, isFalse, reason: 'never a frame of the whole file');
    expect(p.active, isTrue);
    expect(s.isReplay, isTrue);
    expect(s.nowMs, DateTime.utc(2021, 12, 31, 23, 59, 59).millisecondsSinceEpoch, reason: 'the last bar before the start date');
    expect(f.advances, ['2021-12-31 23:59:59'], reason: 'the engine catches up with the cursor (no ticks before --from)');
    expect(p.engineMs, DateTime.utc(2021, 12, 31, 23, 59, 59).millisecondsSinceEpoch);
    s.exitReplay();
    s.toggleSelect();
    expect(s.isReplay && !s.selectMode, isTrue, reason: 'locked while practising');
    expect(s.notice, contains('Practice keeps the chart in replay'));
    // a request goes out at the newest point only
    p.ticket
      ..size = '0.1'
      ..sl = '99';
    await p.submit(true);
    expect(f.requests.single.$1, 'buy');
    expect(f.requests.single.$2, {'volume': '0.1', 'sl': '99'});
    s.step(-2);
    expect(p.atHead, isFalse);
    expect(p.canTrade, isFalse);
    await p.submit(false);
    expect(f.requests, hasLength(1), reason: 'nothing is sent while looking back');
    p.backToLatest();
    expect(p.atHead, isTrue);
    await p.pause();
    expect(s.practiceLock, isFalse);
    expect(lab.settings.practice?['out'], p.saved?['out']);
    lab.dispose();
  });

  test('advances are coalesced: one in flight, then the latest cursor', () async {
    final (lab, f, _) = await _lab();
    final s = lab.chart, p = lab.practice;
    await p.start(data: lab.settings.dataFile, startDate: '2022-01-01');
    await _idle(p);
    f.hold = Completer<void>();
    s.step(1); // 00:00 bar
    s.step(1);
    s.step(1); // 00:30 bar
    await until(() => f.advances.length == 2);
    expect(f.advances.last, '2022-01-01 00:14:59', reason: 'the first step went out; the others wait');
    f.hold!.complete();
    f.hold = null;
    await _idle(p);
    expect(f.advances, ['2021-12-31 23:59:59', '2022-01-01 00:14:59', '2022-01-01 00:44:59']);
    expect(p.reachedMs, DateTime.utc(2022, 1, 1, 0, 44, 59).millisecondsSinceEpoch);
    s.step(-1);
    s.step(1);
    await _idle(p);
    expect(f.advances, hasLength(3), reason: 'stepping back and forth to the head sends nothing');
    lab.dispose();
  });

  test('a protected period is entered only after a logged confirmation', () async {
    final (lab, f, _) = await _lab(protect: const ProtectedPeriod('2022-01-01'));
    final s = lab.chart, p = lab.practice;
    expect(p.protectedAtStart('2021-12-31'), isNull);
    expect(p.protectedAtStart('2022-01-01'), const ProtectedPeriod('2022-01-01'));
    await p.start(data: lab.settings.dataFile, startDate: '2021-12-31');
    await _idle(p);
    final edge = DateTime.utc(2022).millisecondsSinceEpoch;
    s.togglePlay();
    await until(() => p.needsConfirm != null, what: 'the hold at the boundary');
    expect(s.playing, isFalse);
    expect(s.nowMs, lessThan(edge), reason: 'held before the period');
    await _idle(p);
    expect(f.advances.every((a) => a.compareTo('2022-01-01') < 0), isTrue, reason: 'the engine never went in');
    expect(p.canTrade, isFalse);
    // stepping again holds again
    s.step(1);
    expect(s.nowMs, lessThan(edge));
    await p.confirmProtected();
    final c = readConfirmation(p.out!);
    expect(c?.covers(const ProtectedPeriod('2022-01-01')), isTrue);
    expect(c?.strategy, kPracticeKey);
    s.step(1);
    await _idle(p);
    expect(s.nowMs, greaterThan(edge));
    expect(f.advances.last, '2022-01-01 00:14:59');
    lab.dispose();
  });

  test('random start: a weekday 30 days in, outside the protected period', () {
    final first = DateTime.utc(2021, 1, 4).millisecondsSinceEpoch, last = DateTime.utc(2026, 10, 8).millisecondsSinceEpoch;
    const p = ProtectedPeriod('2024-01-01');
    for (var k = 0; k < 200; k++) {
      final d = PracticeState.randomStart(first, last, p)!;
      expect(d.weekday, lessThanOrEqualTo(5));
      expect(d.isBefore(DateTime.utc(2024)), isTrue);
      expect(d.isAfter(DateTime.utc(2021, 2, 2)), isTrue);
    }
  });
}
