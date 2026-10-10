import 'package:strategy_lab/data/events.dart';
import 'package:strategy_lab/data/loaders.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  group('candles CSV', () {
    test('parses downloader format, detects timeframe', () {
      final c = parseCandlesFile(writeTemp('c.csv', candlesCsv(10, ohlc: {3: [1, 2, 0.5, 1.5]})));
      expect(c.length, 10);
      expect(c.minutes, 15);
      expect(c.tf, 'M15');
      expect(c.key(0), '2022-03-01 00:00:00');
      expect(c.key(3), '2022-03-01 00:45:00');
      expect([c.o[3], c.h[3], c.l[3], c.c[3]], [1, 2, 0.5, 1.5]);
      expect(c.time(1), DateTime.utc(2022, 3, 1, 0, 15));
      expect(c.indexOf(DateTime.utc(2022, 3, 1, 0, 30).millisecondsSinceEpoch), 2);
    });

    test('accepts a BOM and quoted fields', () {
      final c = parseCandlesFile(writeTemp('c.csv', '﻿"time","open","high","low","close","volume"\n"2022-03-01 00:00:00",1,2,0.5,1.5,3\n'));
      expect(c.key(0), '2022-03-01 00:00:00');
      expect(c.v.single, 3);
    });

    test('rejects wrong files with a clear message', () {
      expect(() => parseCandlesFile(writeTemp('c.txt', 'x')), throwsA(isA<LoadError>().having((e) => e.message, 'm', contains("isn't a CSV"))));
      expect(() => parseCandlesFile(writeTemp('c.csv', 'time,open,high\n2022-03-01 00:00:00,1,2\n')),
          throwsA(isA<LoadError>().having((e) => e.message, 'm', contains('missing low, close'))));
      expect(() => parseCandlesFile(writeTemp('c.csv', '$eventsHeader\n2022-03-01 01:00:00,x\n')),
          throwsA(isA<LoadError>().having((e) => e.message, 'm', contains('FVG events file'))));
      final backwards = 'time,open,high,low,close\n2022-03-01 00:15:00,1,1,1,1\n2022-03-01 00:00:00,1,1,1,1\n';
      expect(() => parseCandlesFile(writeTemp('c.csv', backwards)),
          throwsA(isA<LoadError>().having((e) => e.message, 'm', contains('backwards or repeat'))));
    });
  });

  group('events CSV', () {
    const row = '2022-03-01 01:00:00,2022-03-01 02:00:00,2022-03-01 03:00:00,101.0,100.0,bull,0.5,4,0.62,0.1,bounce,4.0,bounce_inside_gap,Q2';

    test('parses fvg_events.csv; derives sessions from UTC hours when no column', () {
      final r = parseEventsFile(writeTemp('fvg_events.csv', '$eventsHeader\n$row\n'));
      final e = r.events.single;
      expect(e.id, '2022-03-01 01:00:00|bull');
      expect(e.isBull, isTrue);
      expect(e.gap, 1.0);
      expect(e.outcome, EvOutcome.bounce);
      expect(e.bars, 4);
      expect(e.age, 4);
      expect(e.session, 'Asia');
      expect(e.touchSession, 'Asia');
      expect(e.dispQ, isNull);
      expect(e.period, Period.inSample);
      expect(r.columns.contains('disp_q'), isFalse);
    });

    test('reads the fvg_conditions.py columns of fvg_events_app.csv', () {
      final head = '$eventsHeader,disp_q,trend,age_b,form_session,touch_session,sweep_b,period';
      final r = parseEventsFile(writeTemp('fvg_events_app.csv',
          '$head\n$row,D4 strong,aligned,4-12,London,New York,after sweep,out\n${row.replaceFirst('bull', 'bear')},D1 weak,against,1-3 bars,Asia,Asia,no sweep,in\n'));
      final a = r.events.firstWhere((e) => e.isBull), b = r.events.firstWhere((e) => !e.isBull);
      expect([a.dispQ, a.htfTrend, a.session, a.touchSession, a.sweep, a.period, a.ageBucket],
          ['D4 strong', 'Aligned', 'London', 'New York', true, Period.outOfSample, '4–12']);
      expect([b.dispQ, b.htfTrend, b.sweep, b.period], ['D1 weak', 'Against', false, Period.inSample]);
      expect(r.columns, containsAll(['disp_q', 'htf_trend', 'sweep']));
    });

    test('companion files need only time, dir, outcome; control rows keep their kind', () {
      final r = parseEventsFile(
          writeTemp('fvg_control_events.csv', 'time,dir,outcome,age,form_session,period,kind\n2022-03-01 01:00:00,bear,through,2,Asia,in,real\n2022-03-01 01:15:00,bull,timeout,7,Asia,in,fake\n'),
          companion: true);
      expect(r.events.map((e) => e.kind), ['real', 'fake']);
      expect(r.events.first.outcome, EvOutcome.through);
      expect(r.events.last.age, 7);
    });

    test('skips unreadable rows and reports them; rejects candle files', () {
      final r = parseEventsFile(writeTemp('fvg_events.csv', '$eventsHeader\n$row\nnot,a,row\n'));
      expect(r.events, hasLength(1));
      expect(r.skipped, 1);
      expect(() => parseEventsFile(writeTemp('fvg_events.csv', candlesCsv(3))),
          throwsA(isA<LoadError>().having((e) => e.message, 'm', contains('candle file'))));
      expect(() => parseEventsFile(writeTemp('fvg_events.csv', 'time,dir\n')), throwsA(isA<LoadError>()));
    });
  });

  group('real study files', () {
    test('M1 candles: 2,044,519 bars, first and last as in the file', () {
      final c = parseCandlesFile(fx(kM1));
      expect(c.length, 2044519);
      expect(c.tf, 'M1');
      expect(c.key(0), '2021-01-03 23:00:00');
      expect(c.o[0], 1904.998);
      expect(c.key(c.length - 1), '2026-10-07 23:59:00');
    }, skip: skipUnlessFxdata([kM1]), timeout: const Timeout(Duration(minutes: 2)));

    test('fvg_events.csv and fvg_events_app.csv: 18,359 rows each, nothing skipped', () {
      final a = parseEventsFile(fx('fvg_events.csv')), b = parseEventsFile(fx('fvg_events_app.csv'));
      expect(a.events, hasLength(18359));
      expect(b.events, hasLength(18359));
      expect(a.skipped + b.skipped, 0);
      expect(b.events.where((e) => e.dispQ == null || e.htfTrend == null || e.sweep == null), isEmpty);
    }, skip: skipUnlessFxdata(['fvg_events.csv', 'fvg_events_app.csv']));
  });
}
