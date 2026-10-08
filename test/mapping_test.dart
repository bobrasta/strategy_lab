import 'package:backy/data/events.dart';
import 'package:backy/data/loaders.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  test('maps formation/touch/end to bar indices by exact time text; counts misses', () {
    final c = parseCandlesFile(writeTemp('c.csv', candlesCsv(20)));
    final r = parseEventsFile(writeTemp('fvg_events.csv', '$eventsHeader\n'
        '2022-03-01 01:00:00,2022-03-01 02:00:00,2022-03-01 03:00:00,101,100,bull,0.5,4,0.2,0,bounce,4,bounce_inside_gap,Q2\n'
        // same instant written differently: must NOT match (exact string rule)
        '2022-03-01T01:15:00,2022-03-01 02:00:00,2022-03-01 03:00:00,101,100,bull,0.5,3,0.2,0,bounce,4,bounce_inside_gap,Q2\n'
        // touch outside the candle file
        '2022-03-01 01:30:00,2022-03-09 02:00:00,2022-03-09 03:00:00,99,100,bear,0.5,3,0.2,0,through,1,broke_through,Q2\n'));
    final miss = mapEvents(r.events, c);
    expect(miss, 2);
    final ok = r.events.firstWhere((e) => e.time == '2022-03-01 01:00:00');
    expect([ok.formedIdx, ok.touchIdx, ok.endIdx], [4, 8, 12]);
    expect(r.events.where((e) => !e.mapped), hasLength(2));
  });

  test('end index never precedes the touch index', () {
    final c = parseCandlesFile(writeTemp('c.csv', candlesCsv(20)));
    final r = parseEventsFile(writeTemp('fvg_events.csv', '$eventsHeader\n'
        '2022-03-01 01:00:00,2022-03-01 02:00:00,2022-03-01 01:45:00,101,100,bull,0.5,4,0.2,0,timeout,,no_resolution,Q2\n'));
    mapEvents(r.events, c);
    expect(r.events.single.endIdx, r.events.single.touchIdx);
  });

  test('all 18,359 study events map onto the M15 file', () {
    final c = parseCandlesFile(fx(kM15));
    final r = parseEventsFile(fx('fvg_events_app.csv'));
    expect(mapEvents(r.events, c), 0);
    final first = r.events.first;
    expect(c.keys[first.formedIdx], first.time);
    expect(c.keys[first.touchIdx], first.touchTime);
    expect(first.touchIdx - first.formedIdx, first.age);
  }, skip: skipUnlessFxdata([kM15, 'fvg_events_app.csv']));
}
