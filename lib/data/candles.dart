import 'dart:typed_data';

const kTimeframes = ['M1', 'M5', 'M15', 'H1'];

String tfLabel(int minutes) => switch (minutes) {
      1 => 'M1',
      5 => 'M5',
      15 => 'M15',
      30 => 'M30',
      60 => 'H1',
      240 => 'H4',
      1440 => 'D1',
      _ => 'M$minutes',
    };

int tfMinutes(String tf) => switch (tf) {
      'H1' => 60,
      'H4' => 240,
      'D1' => 1440,
      _ => int.tryParse(tf.substring(1)) ?? 15,
    };

String _p2(int v) => v.toString().padLeft(2, '0');

/// Same text format as the downloader: 2021-01-03 23:00:00
String formatKey(int ms) {
  final t = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  return '${t.year}-${_p2(t.month)}-${_p2(t.day)} ${_p2(t.hour)}:${_p2(t.minute)}:${_p2(t.second)}';
}

/// Columnar OHLCV series (UTC). Columns keep 1.8M M1 rows cheap to hold and
/// to send between isolates.
class Candles {
  Candles({
    required this.minutes,
    required this.t,
    required this.o,
    required this.h,
    required this.l,
    required this.c,
    required this.v,
    required this.keys,
  });

  final int minutes;

  /// Bar open time, ms since epoch UTC.
  final Int64List t;
  final Float64List o, h, l, c, v;

  /// Exact time text per bar (as written in the file, or formatKey for resampled bars).
  /// Events are matched to bars by exact string equality on these.
  final List<String> keys;
  Map<String, int>? _index;

  String get tf => tfLabel(minutes);
  int get length => t.length;
  DateTime time(int i) => DateTime.fromMillisecondsSinceEpoch(t[i], isUtc: true);

  Map<String, int> get index {
    final m = _index;
    if (m != null) return m;
    final built = <String, int>{};
    for (var i = 0; i < keys.length; i++) {
      built[keys[i]] = i;
    }
    return _index = built;
  }

  /// First bar with time >= [ms].
  int lowerBound(int ms) {
    var lo = 0, hi = t.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (t[mid] < ms) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }
}
