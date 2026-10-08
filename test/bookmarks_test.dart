import 'dart:convert';
import 'dart:io';

import 'package:backy/data/bookmarks.dart';
import 'package:backy/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('stars and notes save to fvg_bookmarks.json next to the events file and load back', () async {
    final events = writeTemp('fvg_events.csv', '$eventsHeader\n'
        '2022-03-01 01:00:00,2022-03-01 02:00:00,2022-03-01 03:00:00,101,100,bull,0.5,4,0.2,0,bounce,4,bounce_inside_gap,Q2\n');
    final s = AppState();
    await s.loadEvents(events);
    const id = '2022-03-01 01:00:00|bull';
    s.toggleStar(id);
    s.setNote(id, 'clean retest, NY open');
    await s.bookmarks.save();

    final file = File('${File(events).parent.path}/fvg_bookmarks.json');
    expect(file.existsSync(), isTrue);
    expect(jsonDecode(file.readAsStringSync()), {id: {'starred': true, 'note': 'clean retest, NY open'}});

    s.toggleStarredOnly();
    expect(s.stats.total, 1);

    final again = await BookmarkStore.load(file.path);
    expect(again.starred(id), isTrue);
    expect(again.note(id), 'clean retest, NY open');
    expect(again.starredCount, 1);
  });

  test('unstarred, empty-note entries are dropped; a broken file does not block loading', () async {
    final path = writeTemp('fvg_bookmarks.json', '{not json');
    final b = await BookmarkStore.load(path);
    expect(b.starredCount, 0);
    b.toggleStar('a|bull');
    b.toggleStar('a|bull');
    await b.save();
    expect(jsonDecode(File(path).readAsStringSync()), isEmpty);
  });
}
