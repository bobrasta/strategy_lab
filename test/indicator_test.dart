import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:strategy_lab/chart/chart_geometry.dart';
import 'package:strategy_lab/chart/chart_layer.dart';
import 'package:strategy_lab/chart/indicator_layer.dart';
import 'package:strategy_lab/indicators/indicator_output.dart';
import 'package:strategy_lab/indicators/indicators_state.dart';
import 'package:strategy_lab/run/run_data.dart';
import 'package:strategy_lab/run/run_view.dart';

import 'support.dart';

const big = 1 << 60;

/// The values shown at [now], as runs of (bar minute, value) split at EMPTY_VALUE gaps.
List<List<(int, double)>> runs(PlotSeries s, int now, {int from = -big, int to = big}) {
  final out = <List<(int, double)>>[[]];
  walkPlot(s, from, to, now, (t, v) => out.last.add(((t - at(0)) ~/ 60000, v)), () {
    if (out.last.isNotEmpty) out.add([]);
  });
  return out.where((r) => r.isNotEmpty).toList();
}

/// A run's drawing state at [now] (RunView, the strategy-drawings logic), as comparable text.
Set<String> runState(RunView v, int now) => {for (final o in v.drawingsAt(now)) _key(o)};
String _key(DrawObj o) => '${o.name}|${o.kind}|${o.color}|${o.label}|${o.shape}|${o.t1}|${o.p1}|${o.t2}|${o.p2}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('an output folder parses: plots from indicator.json, records per plot, gaps, objects, journal', () {
    final o = loadIndicatorOutput(writeFakeIndicator().path);
    expect(o.plots.map((p) => (p.index, p.name, p.label, p.color, p.dashed, p.width)), [
      (0, 'Mid', 'Middle', 'blue', false, 1.5),
      (1, 'Upper', 'Upper band', 'amber', true, 1.0),
    ]);
    expect(o.plotRecords, 120 + 12 + 1, reason: 'header and nothing else skipped');
    final mid = o.series[0]!;
    expect(mid.length, 121);
    expect(mid.valueAt(at(40), big)!.isNaN, isTrue, reason: 'empty value = EMPTY_VALUE');
    expect(mid.valueAt(at(39), big), 100.39);
    expect(o.series[1]!.length, 12);
    expect(o.drawings.events, 7, reason: 'the truncated last line is skipped');
    expect(o.drawings.lives, 4, reason: 'g, mk, ln, and g again after its delete');
    expect(o.journal.map((j) => j.text), ['Band(5) on XAUUSD', 'done']);
  });

  test('plots.csv without a header and with \\r\\n line ends parses the same', () {
    final d = writeFakeIndicator(header: false);
    final f = File('${d.path}/plots.csv');
    f.writeAsStringSync(f.readAsStringSync().replaceAll('\n', '\r\n'));
    final o = loadIndicatorOutput(d.path);
    expect(o.plotRecords, 133);
    expect(o.series[0]!.valueAt(at(61), big), 100.61);
  });

  test('a repainted bar shows the old value before the second stamp and the new one from it', () {
    final mid = loadIndicatorOutput(writeFakeIndicator().path).series[0]!;
    // bar 60 (01:00): first Set at 01:01:00 → 100.6; repainted at 01:10:00 → 101.5
    expect(mid.valueAt(at(60), at(60, 59)), isNull, reason: 'not known while its bar forms');
    expect(mid.valueAt(at(60), at(61)), 100.6);
    expect(mid.valueAt(at(60), at(69, 59)), 100.6);
    expect(mid.valueAt(at(60), at(70)), 101.5);
    expect(mid.valueAt(at(60), big), 101.5);
    // The same through the walk the painter uses.
    double shownAt60(int now) => runs(mid, now).expand((r) => r).firstWhere((p) => p.$1 == 60).$2;
    expect(shownAt60(at(69, 59)), 100.6);
    expect(shownAt60(at(70)), 101.5);
  });

  test('nothing stamped after now is shown, for every cursor second-by-bar', () {
    final o = loadIndicatorOutput(writeFakeIndicator().path);
    for (final s in o.series.values) {
      for (var bar = 0; bar <= 121; bar++) {
        for (final now in [at(bar), at(bar, 59)]) {
          final shown = s.visible(-big, big, now).toList();
          for (final k in shown) {
            expect(s.stamp[k], lessThanOrEqualTo(now));
          }
          // Exactly one record per bar time known by now: the latest one.
          final times = {for (var k = 0; k < s.length; k++) if (s.stamp[k] <= now) s.time[k]};
          expect(shown.map((k) => s.time[k]).toList(), times.toList()..sort());
          for (final k in shown) {
            expect(k + 1 < s.length && s.time[k + 1] == s.time[k] && s.stamp[k + 1] <= now, isFalse, reason: 'a newer record for that bar is known');
          }
        }
      }
    }
    // Bar 119's value is stamped 02:00:00: never shown with the run, which ends at 01:59:59.
    expect(o.series[0]!.valueAt(at(119), at(119, 59)), isNull);
  });

  test('EMPTY_VALUE breaks the line', () {
    final mid = loadIndicatorOutput(writeFakeIndicator().path).series[0]!;
    final r = runs(mid, at(119, 59));
    expect(r, hasLength(2));
    expect(r[0].first.$1, 0);
    expect(r[0].last.$1, 39);
    expect(r[1].first.$1, 45);
    expect(r[1].last.$1, 118);
    expect(runs(mid, at(42, 59)), hasLength(1), reason: 'the gap bars are known, nothing after them yet');
  });

  test('a window shows its records plus one either side', () {
    final up = loadIndicatorOutput(writeFakeIndicator().path).series[1]!; // every 10th bar
    final shown = [for (final k in up.visible(at(25), at(55), big)) (up.time[k] - at(0)) ~/ 60000];
    expect(shown, [20, 30, 40, 50, 60]);
  });

  test('objects at any cursor equal the strategy-drawings state of the same file', () {
    final d = writeFakeIndicator();
    final o = loadIndicatorOutput(d.path);
    final events = [for (final l in File('${d.path}/drawings.jsonl').readAsLinesSync()) ?parseDrawLine(l)];
    final manifest = RunManifest(dir: d.path, json: const {}, modifiedMs: 0);
    final view = RunView(RunData(manifest: manifest, trades: const [], dealHeader: const [], deals: const [], drawings: events, journal: const []), null);
    for (var bar = 0; bar < 125; bar++) {
      for (final now in [at(bar), at(bar, 59)]) {
        expect({for (final x in o.drawings.objectsAt(now, -big, big)) _key(x)}, runState(view, now), reason: 'at minute $bar');
      }
    }
    // Spot checks: the zone is open-ended until the move at 00:30, gone 01:30..01:39, back at 01:40.
    DrawObj? g(int now) => o.drawings.objectsAt(now, -big, big).where((x) => x.name == 'g').firstOrNull;
    expect(g(at(11, 59)), isNull);
    expect(g(at(29, 59))!.t2, isNull);
    expect(g(at(30))!.t2, at(30));
    expect(g(at(95)), isNull);
    expect(g(at(100))!.t1, at(95));
    expect(g(at(100))!.color, 'red');
  });

  test('objects outside the view are culled by time', () {
    final o = loadIndicatorOutput(writeFakeIndicator().path).drawings;
    final names = [for (final x in o.objectsAt(at(60), at(0), at(15))) x.name];
    expect(names, ['g'], reason: 'the marker (00:19) and the line (00:45 →) are right of the view');
    expect([for (final x in o.objectsAt(at(29), at(25), at(28))) x.name], contains('g'), reason: 'at 00:29 the zone is open-ended: it reaches now');
    expect([for (final x in o.objectsAt(at(25), at(31), at(40))) x.name], isEmpty, reason: 'an open-ended zone reaches now, not the future');
    expect([for (final x in o.objectsAt(at(60), at(31), at(40))) x.name], isNot(contains('g')), reason: 'the zone ended at 00:30');
    expect([for (final x in o.objectsAt(at(60), at(46), at(47))) x.name], contains('ln'), reason: 'open-ended: reaches now');
  });

  test('the layer draws in Explore and Replay only for the chart\'s data file', () async {
    final s = await openFakeRun(writeFakeRun());
    final i = IndicatorInstance(1, 'band', const {})..output = loadIndicatorOutput(writeFakeIndicator().path);
    i.dataFile = '/elsewhere.csv';
    expect(i.layer.isOn(s), isFalse);
    i.dataFile = s.candlesPath;
    expect(i.layer.isOn(s), isTrue);
    i.visible = false;
    expect(i.layer.isOn(s), isFalse);
    i.visible = true;
    s.setIndicatorLayers([i.layer]);
    expect(layersOf(s).last, same(i.layer));
    void paint() {
      final rec = PictureRecorder(), canvas = Canvas(rec);
      final g = ChartGeometry.compute(const Size(1200, 700), s, s.candles!, s.visibleCursor, 0);
      final ctx = LayerContext(state: s, candles: s.candles!, cursor: s.visibleCursor, nowMs: s.nowMs);
      i.layer.paintBelow(canvas, g, ctx);
      i.layer.paintAbove(canvas, g, ctx);
      rec.endRecording();
    }

    paint();
    s.fit();
    paint();
    s.enterReplay();
    for (final bar in [0, 12, 44, 60, 70, 119]) {
      s.startAt(bar);
      paint();
    }
    for (final tf in ['M5', 'M15']) {
      await s.setTimeframe(tf);
      paint();
    }
  });

  test('labels list the non-default inputs in schema order', () {
    final sc = IndicatorSchema.fromJson(bandInputs());
    expect(indicatorLabel('band', const {}, sc), 'band');
    expect(indicatorLabel('band', const {'Width': '0.25', 'Tf': 'M15'}, sc), 'band (M15, 0.25)');
    expect(indicatorLabel('band', const {'Period': '5'}, sc), 'band', reason: 'a default value is not listed');
    expect(indicatorLabel('fvg', const {'Tf': 'M15', 'MinGapAtr': '0.10'}, null), 'fvg (M15, 0.10)');
    // `schema` may also be the inputs list itself.
    final flat = IndicatorSchema.fromJson({'schema': (bandInputs()['schema'] as Map)['inputs'], 'plots': bandPlots});
    expect(flat.inputs.map((i) => i.name), ['Tf', 'Period', 'Width']);
    expect(flat.plots, hasLength(2));
  });

  test('scale: 2M plot records and 300k drawing events parse in an isolate; lookups stay fast', () async {
    final d = Directory('${tempDir().path}/big')..createSync();
    final t0 = DateTime.utc(2021, 1, 4).millisecondsSinceEpoch;
    String k(int ms) => key(DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true));
    File('${d.path}/indicator.json').writeAsStringSync('{"kind":"indicator","plots":[{"index":0,"name":"L","label":"L","color":"blue","style":"solid","width":1}]}');
    final pb = StringBuffer('stamp,plot,time,value\n');
    for (var i = 0; i < 2000000; i++) {
      pb.write('${k(t0 + (i + 1) * 60000)},0,${k(t0 + i * 60000)},${1800 + (i % 1000) / 100}\n');
    }
    File('${d.path}/plots.csv').writeAsStringSync(pb.toString());
    final db = StringBuffer();
    for (var i = 0; i < 100000; i++) {
      final c = t0 + i * 15 * 60000;
      db.write('{"time":"${k(c + 900000)}","op":"create","name":"z$i","kind":"zone","t1":"${k(c)}","p1":1801.5,"t2":null,"p2":1800.5,"color":"green","label":"FVG"}\n');
      db.write('{"time":"${k(c + 1800000)}","op":"move","name":"z$i","kind":"zone","t1":"${k(c)}","p1":1801.5,"t2":"${k(c + 1800000)}","p2":1800.5}\n');
      db.write('{"time":"${k(c + 2700000)}","op":"create","name":"m$i","kind":"marker","t1":"${k(c)}","p1":1801.0,"color":"red","label":"x","shape":"dot"}\n');
    }
    File('${d.path}/drawings.jsonl').writeAsStringSync(db.toString());
    final path = d.path;
    final sw = Stopwatch()..start();
    final o = await Isolate.run(() => loadIndicatorOutput(path));
    final parseMs = sw.elapsedMilliseconds;
    expect(o.plotRecords, 2000000);
    expect(o.drawings.lives, 200000);
    // A 5,000-bar window in the middle, at its end (what one frame asks for).
    final from = t0 + 1000000 * 60000, to = from + 5000 * 60000;
    var n = 0;
    final sp = Stopwatch(), so = Stopwatch();
    for (var rep = 0; rep < 20; rep++) {
      sp.start();
      n = o.series[0]!.visible(from, to, to).length;
      sp.stop();
      so.start();
      o.drawings.objectsAt(to + rep, from, to); // + rep defeats the memo
      so.stop();
    }
    final plotMs = sp.elapsedMicroseconds / 20000, objMs = so.elapsedMicroseconds / 20000, lookMs = plotMs + objMs;
    expect(n, 5001, reason: 'one before the window, then bars whose value is stamped by its end');
    // ignore: avoid_print
    print('indicator scale: parse $parseMs ms (isolate, JIT), one frame\'s lookups: plot ${plotMs.toStringAsFixed(2)} ms, objects ${objMs.toStringAsFixed(2)} ms');
    expect(lookMs, lessThan(50));
  }, timeout: const Timeout(Duration(minutes: 3)));
}
