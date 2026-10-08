import 'package:backy/data/events.dart';
import 'package:backy/data/loaders.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  test('session from UTC hour: Asia 00–06, London 07–12, New York 13–20, Off-hours 21–23', () {
    final want = {
      for (var h = 0; h <= 6; h++) h: 'Asia',
      for (var h = 7; h <= 12; h++) h: 'London',
      for (var h = 13; h <= 20; h++) h: 'New York',
      for (var h = 21; h <= 23; h++) h: 'Off-hours',
    };
    for (final e in want.entries) {
      expect(sessionForHour(e.key), e.value, reason: 'hour ${e.key}');
    }
  });

  test('session labels from files normalise', () {
    expect(normalizeSession('Asia'), 'Asia');
    expect(normalizeSession('new_york'), 'New York');
    expect(normalizeSession('NY'), 'New York');
    expect(normalizeSession('off-hours'), 'Off-hours');
    expect(normalizeSession(''), isNull);
  });

  test('loader derives formation and touch sessions from their own times', () {
    final r = parseEventsFile(writeTemp('fvg_events.csv', '$eventsHeader\n'
        '2022-03-01 06:45:00,2022-03-01 07:00:00,2022-03-01 08:00:00,101,100,bull,0.5,1,0.2,0,bounce,4,bounce_inside_gap,Q2\n'
        '2022-03-01 20:45:00,2022-03-01 21:00:00,2022-03-01 22:00:00,101,100,bull,0.5,1,0.2,0,bounce,4,bounce_inside_gap,Q2\n'));
    expect(r.events.map((e) => '${e.session}/${e.touchSession}'), ['Asia/London', 'New York/Off-hours']);
  });

  test('age buckets and periods match fvg_conditions.py', () {
    expect([1, 3, 4, 12, 13, 48, 49].map((a) => normalizeAge(a <= 3 ? '1-3 bars' : a <= 12 ? '4-12' : a <= 48 ? '13-48' : '49+')),
        ['1–3', '1–3', '4–12', '4–12', '13–48', '13–48', '49+']);
    expect(periodOf(DateTime.utc(2023, 12, 31, 23, 45).millisecondsSinceEpoch), Period.inSample);
    expect(periodOf(DateTime.utc(2024).millisecondsSinceEpoch), Period.outOfSample);
    expect(periodOf(DateTime.utc(2026).millisecondsSinceEpoch), Period.holdout);
    expect(['in', 'out', 'holdout'].map(parsePeriod), [Period.inSample, Period.outOfSample, Period.holdout]);
  });

  test("app sessions equal fvg_conditions.py's form/touch sessions on every study event", () {
    final plain = parseEventsFile(fx('fvg_events.csv')).events; // sessions derived in Dart
    final app = {for (final e in parseEventsFile(fx('fvg_events_app.csv')).events) e.id: e}; // from Python
    var n = 0;
    for (final e in plain) {
      final p = app[e.id]!;
      expect(e.session, p.session, reason: e.id);
      expect(e.touchSession, p.touchSession, reason: e.id);
      expect(e.ageBucket, p.ageBucket, reason: e.id);
      expect(e.period, p.period, reason: e.id);
      n++;
    }
    expect(n, 18359);
  }, skip: skipUnlessFxdata(['fvg_events.csv', 'fvg_events_app.csv']));
}
