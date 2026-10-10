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

/// Same text format as the downloader and the engine: 2021-01-03 23:00:00
String formatKey(int ms) {
  final t = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  return '${t.year}-${_p2(t.month)}-${_p2(t.day)} ${_p2(t.hour)}:${_p2(t.minute)}:${_p2(t.second)}';
}

/// Columnar OHLCV series (UTC). Columns keep 2M M1 rows cheap to hold and
/// to send between isolates (no per-bar objects or strings).
class Candles {
  Candles({
    required this.minutes,
    required this.t,
    required this.o,
    required this.h,
    required this.l,
    required this.c,
    required this.v,
  });

  final int minutes;

  /// Bar open time, ms since epoch UTC.
  final Int64List t;
  final Float64List o, h, l, c, v;

  String get tf => tfLabel(minutes);
  int get length => t.length;
  DateTime time(int i) => DateTime.fromMillisecondsSinceEpoch(t[i], isUtc: true);
  String key(int i) => formatKey(t[i]);

  /// Last instant of bar [i]: the engine's last tick of a bar is at +59 s of its last M1 bar.
  int endMs(int i) => t[i] + minutes * 60000 - 1000;

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

  /// The bar whose bucket holds [ms] (the last bar opening at or before it), or -1.
  int barAt(int ms) => lowerBound(ms + 1) - 1;

  /// Index of the bar opening exactly at [ms], or null.
  int? indexOf(int ms) {
    final i = lowerBound(ms);
    return i < t.length && t[i] == ms ? i : null;
  }

  /// Bars [0, end) as views on the same buffers (no copy).
  Candles head(int end) => end >= length
      ? this
      : Candles(
          minutes: minutes,
          t: Int64List.sublistView(t, 0, end),
          o: Float64List.sublistView(o, 0, end),
          h: Float64List.sublistView(h, 0, end),
          l: Float64List.sublistView(l, 0, end),
          c: Float64List.sublistView(c, 0, end),
          v: Float64List.sublistView(v, 0, end),
        );
}
