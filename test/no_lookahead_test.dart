import 'dart:ui';

import 'package:backy/chart/chart_geometry.dart';
import 'package:backy/chart/chart_layer.dart';
import 'package:backy/chart/fvg_layer.dart';
import 'package:backy/data/events.dart';
import 'package:backy/data/predictions.dart';
import 'package:backy/state/app_state.dart';
import 'package:backy/theme.dart';
import 'package:backy/widgets/chart_overlays.dart' show visibleOutcome;
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

// One known bullish gap on synthetic M15 bars:
// formed at bar 10 (02:30), first touch at bar 15 (03:45), resolves (bounce) at bar 20 (05:00).
// The touch bar's high is 150 so any autoscale leak of that bar is obvious.
const formed = 10, touch = 15, end = 20;

Future<AppState> load() async {
  final c = writeTemp('xauusd_m15_test.csv', candlesCsv(60, ohlc: {touch: [100.2, 150.0, 99.8, 100.4]}));
  final e = writeTemp('fvg_events.csv', '$eventsHeader,disp_q,trend,age_b,form_session,touch_session,sweep_b,period\n'
      '2022-03-01 02:30:00,2022-03-01 03:45:00,2022-03-01 05:00:00,101.0,100.0,bull,0.6,5,0.4,0.0,bounce,5.0,bounce_inside_gap,Q3,D4 strong,aligned,4-12,Asia,Asia,no sweep,in\n');
  final s = AppState();
  await s.loadCandles(c);
  await s.loadEvents(e);
  expect(s.error, isNull);
  expect(s.zones, hasLength(1));
  return s;
}

LayerContext ctx(AppState s) => LayerContext(state: s, candles: s.candles!, cursor: s.visibleCursor, pulse: 0);

double autoscaleHi(AppState s) => ChartGeometry.compute(const Size(1200, 700), s, s.candles!, s.visibleCursor, 0).hi;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('replay: zone hidden before formation, grey until end_time, outcome colour from end_time', () async {
    final s = await load();
    final z = s.zones.single;
    expect([z.formed, z.touch, z.end], [formed, touch, end]);
    s.enterReplay();
    s.startAt(0);
    for (var bar = 0; bar <= 30; bar++) {
      expect(s.visibleCursor, bar);
      final known = FvgLayer.outcomeKnown(z, ctx(s));
      expect(known, bar >= end, reason: 'bar $bar');
      expect(FvgLayer.zoneColor(z, ctx(s)), bar >= end ? C.green : C.mute, reason: 'bar $bar');
      expect(visibleOutcome(s, z.ev), bar >= end ? EvOutcome.bounce : null, reason: 'events table, bar $bar');
      // Running counters never count the future.
      expect(s.openGaps, bar >= formed && bar < end ? 1 : 0, reason: 'bar $bar');
      expect(s.resolvedCount, bar >= end ? 1 : 0, reason: 'bar $bar');
      s.step(1);
    }
  });

  test('autoscale only reads bars at or before the cursor', () async {
    final s = await load();
    s.enterReplay();
    s.startAt(touch - 1);
    expect(autoscaleHi(s), lessThan(110));
    s.step(1);
    expect(s.visibleCursor, touch);
    expect(autoscaleHi(s), greaterThan(150));
  });

  test('predict: touch bar hidden (open only) while the call is pending, revealed after', () async {
    final s = await load();
    s.enterReplay();
    s.togglePredict();
    s.startAt(5);
    for (var i = 0; i < 30 && s.peek == null; i++) {
      s.step(1);
    }
    expect(s.visibleCursor, touch - 1, reason: 'cursor stops on the bar before the touch');
    expect(s.peek, touch, reason: 'only this bar\'s open is drawn');
    expect(s.pending, s.zones.single.ev.id);
    expect(autoscaleHi(s), lessThan(110), reason: 'the hidden bar\'s high must not move the scale');
    expect(visibleOutcome(s, s.zones.single.ev), isNull);

    // Nothing moves the cursor past the touch until the call is made.
    s.step(1);
    s.togglePlay();
    s.nextTouch();
    s.nextEvent();
    expect(s.visibleCursor, touch - 1);
    expect(s.playing, isFalse);

    s.guess('bounce');
    expect(s.peek, isNull);
    expect(s.visibleCursor, touch);
    expect(autoscaleHi(s), greaterThan(150));
    expect(s.predictionLog, hasLength(1));
    expect(s.predictionLog.single.correct, isTrue);
    // The outcome still isn't shown until end_time.
    expect(FvgLayer.outcomeKnown(s.zones.single, ctx(s)), isFalse);
  });

  test('Next touch (N) stops just before the touch bar', () async {
    final s = await load();
    s.enterReplay();
    s.startAt(0);
    s.nextTouch();
    expect(s.visibleCursor, touch - 1);
    expect(s.peek, isNull);
  });

  test('100 bars/s advances ~100 bars per second with at most ~60 repaints', () async {
    final s = await load();
    s.enterReplay();
    s.startAt(0);
    s.setSpeed(100);
    var notes = 0;
    s.addListener(() => notes++);
    s.togglePlay();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    s.togglePlay();
    expect(s.visibleCursor, inInclusiveRange(40, 51), reason: '~50 bars in 0.5 s');
    expect(notes, lessThanOrEqualTo(36), reason: '16 ms tick: ≤ ~31 frames in 0.5 s plus play/pause');
    expect(notes, greaterThan(5));
  });

  test('prediction export carries the conditions at the time of the call', () async {
    final s = await load();
    final csv = predictionsCsv([PredictionRecord.of(s.zones.single.ev, 'break', DateTime.utc(2026, 10, 9, 12))]);
    final lines = csv.trim().split('\n');
    expect(lines.first, 'formation_time,dir,scenario,size_q,disp_q,formation_session,touch_session,htf_trend,age_bucket,sweep,period,call,actual,correct,answered_at');
    expect(lines[1], '2022-03-01 02:30:00,bull,bounce_inside_gap,Q3,D4 strong,Asia,Asia,Aligned,4–12,no,In-sample,break,bounce,false,2026-10-09T12:00:00.000Z');
  });
}
