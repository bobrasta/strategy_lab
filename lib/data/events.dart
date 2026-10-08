import 'dart:math';

import 'candles.dart';

enum EvOutcome { bounce, through, timeout }

EvOutcome? parseOutcome(String s) => switch (s.trim().toLowerCase()) {
      'bounce' => EvOutcome.bounce,
      'through' => EvOutcome.through,
      'timeout' => EvOutcome.timeout,
      _ => null,
    };

String outcomeLabel(EvOutcome o) => switch (o) {
      EvOutcome.bounce => 'Bounce',
      EvOutcome.through => 'Break',
      EvOutcome.timeout => 'Timeout',
    };

const kScenarioCodes = [
  'bounce_inside_gap',
  'wick_through_then_bounce',
  'closed_beyond_then_reclaimed',
  'broke_through',
  'no_resolution',
];

const kScenarioLabels = {
  'bounce_inside_gap': 'Bounced inside gap',
  'wick_through_then_bounce': 'Wick through then bounced',
  'closed_beyond_then_reclaimed': 'Closed beyond then reclaimed',
  'broke_through': 'Broke through',
  'no_resolution': 'No resolution',
};

String scenarioLabel(String code) => kScenarioLabels[code] ?? code;

/// Outcome family a scenario belongs to (drives its pill colour).
EvOutcome? scenarioOutcome(String code) => switch (code) {
      'bounce_inside_gap' || 'wick_through_then_bounce' || 'closed_beyond_then_reclaimed' => EvOutcome.bounce,
      'broke_through' => EvOutcome.through,
      'no_resolution' => EvOutcome.timeout,
      _ => null,
    };

const kSessions = ['Asia', 'London', 'New York', 'Off-hours'];

/// Asia 00:00–06:59, London 07:00–12:59, New York 13:00–20:59, Off-hours 21:00–23:59 (UTC).
String sessionForHour(int h) => h < 7
    ? 'Asia'
    : h < 13
        ? 'London'
        : h < 21
            ? 'New York'
            : 'Off-hours';

String? normalizeSession(String raw) {
  final s = raw.trim().toLowerCase().replaceAll('_', ' ').replaceAll('-', ' ');
  if (s.isEmpty) return null;
  if (s.startsWith('asia')) return 'Asia';
  if (s.startsWith('london')) return 'London';
  if (s.startsWith('new york') || s == 'ny' || s == 'newyork') return 'New York';
  if (s.startsWith('off')) return 'Off-hours';
  return null;
}

const kDispBuckets = ['D1 weak', 'D2', 'D3', 'D4 strong'];

String? normalizeDisp(String raw) {
  final s = raw.trim().toUpperCase();
  for (var i = 1; i <= 4; i++) {
    if (s.startsWith('D$i') || s == '$i') return kDispBuckets[i - 1];
  }
  return null;
}

String? normalizeTrend(String raw) {
  final s = raw.trim().toLowerCase();
  if (s.startsWith('align') || s == 'with') return 'Aligned';
  if (s.startsWith('against') || s.startsWith('counter')) return 'Against';
  return null;
}

bool? parseBool(String raw) => switch (raw.trim().toLowerCase()) {
      'yes' || 'true' || '1' || 'y' || 'after sweep' => true,
      'no' || 'false' || '0' || 'n' || 'no sweep' => false,
      _ => null,
    };

const kAgeBuckets = ['1–3', '4–12', '13–48', '49+'];

/// Python's age_b labels ("1-3 bars", "4-12", "13-48", "49+") → [kAgeBuckets].
String? normalizeAge(String raw) {
  final s = raw.trim().replaceAll('–', '-');
  for (var i = 0; i < kAgeBuckets.length; i++) {
    final k = kAgeBuckets[i].replaceAll('–', '-');
    if (s == k || s.startsWith('$k ')) return kAgeBuckets[i];
  }
  return null;
}

enum Period { inSample, outOfSample, holdout }

/// In-sample 2021–23 · Out-of-sample 2024–25 · Hold-out 2026+ (by formation year, UTC).
Period periodOf(int ms) {
  final y = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).year;
  return y >= 2026 ? Period.holdout : (y >= 2024 ? Period.outOfSample : Period.inSample);
}

/// The study's `period` column: "in" / "out" / "holdout".
Period? parsePeriod(String raw) => switch (raw.trim().toLowerCase().replaceAll('-', '').replaceAll('_', '')) {
      'in' || 'insample' => Period.inSample,
      'out' || 'outofsample' => Period.outOfSample,
      'holdout' => Period.holdout,
      _ => null,
    };

String periodLabel(Period p) => switch (p) {
      Period.inSample => 'In-sample',
      Period.outOfSample => 'Out-of-sample',
      Period.holdout => 'Hold-out',
    };

/// One row of fvg_events.csv (one first touch), produced by the Python study.
class FvgEvent {
  FvgEvent({
    required this.time,
    required this.touchTime,
    required this.endTime,
    required this.formationMs,
    required this.touchMs,
    required this.endMs,
    required this.isBull,
    required this.edge,
    required this.far,
    required this.gapAtr,
    required this.age,
    required this.maxWick,
    required this.maxClose,
    required this.outcome,
    required this.bars,
    required this.scenario,
    required this.sizeQ,
    required this.session,
    this.touchSession,
    this.dispQ,
    this.htfTrend,
    this.sweep,
    Period? period,
    this.kind,
  }) : period = period ?? periodOf(formationMs);

  final String time, touchTime, endTime;
  final int formationMs, touchMs, endMs;
  final bool isBull;
  final double edge, far, gapAtr, maxWick, maxClose;

  /// Bars from formation to first touch (−1 when not provided).
  final int age;
  final int? bars;
  final EvOutcome outcome;

  /// [session] is the formation session.
  final String scenario, sizeQ, session;
  final String? touchSession, dispQ, htfTrend;
  final bool? sweep;

  /// From the study's `period` column when present, else from the formation year.
  final Period period;

  /// fvg_control_events.csv only: "real" or "fake" row of the shuffled-bars control run.
  final String? kind;
  bool get isHoldout => period == Period.holdout;
  String? get ageBucket => age < 0
      ? null
      : age <= 3
          ? kAgeBuckets[0]
          : age <= 12
              ? kAgeBuckets[1]
              : age <= 48
                  ? kAgeBuckets[2]
                  : kAgeBuckets[3];

  /// Bar indices on the events' own timeframe (−1 when the time isn't in the candle file).
  int formedIdx = -1, touchIdx = -1, endIdx = -1;

  String get dirCode => isBull ? 'bull' : 'bear';

  /// Bookmark key: formation time + dir.
  String get id => '$time|$dirCode';
  bool get mapped => formedIdx >= 0;
  double get gap => (edge - far).abs();
  double get top => max(edge, far);
  double get bottom => min(edge, far);

  /// Depth 0 = entry edge, 1 = far edge, >1 beyond.
  double priceAtDepth(double d) => isBull ? edge - d * gap : edge + d * gap;
  double target(double k) => isBull ? edge + k * gap : edge - k * gap;
  double fail(double buffer) => isBull ? far - buffer * gap : far + buffer * gap;
}

/// Maps event times to bar indices by exact string match. Returns the number not found.
int mapEvents(List<FvgEvent> evs, Candles c) {
  final idx = c.index;
  var miss = 0;
  for (final e in evs) {
    final f = idx[e.time], t = idx[e.touchTime], en = idx[e.endTime];
    if (f == null || t == null || en == null) {
      e.formedIdx = e.touchIdx = e.endIdx = -1;
      miss++;
    } else {
      e.formedIdx = f;
      e.touchIdx = t;
      e.endIdx = max(en, t);
    }
  }
  return miss;
}

/// An event placed on the current chart's bar indices.
class Zone {
  const Zone(this.ev, this.start, this.formed, this.touch, this.end);
  final FvgEvent ev;

  /// First candle of the 3-candle pattern; [formed] is the third (gap knowable after it closes).
  final int start, formed, touch, end;
}

/// Deepest wick depth from the touch bar up to [upto], from bars only — never past [upto].
double runningDepth(Candles c, Zone z, int upto) {
  final ev = z.ev, g = ev.gap;
  if (g <= 0 || upto < z.touch) return 0;
  final last = min(upto, min(z.end, c.length - 1));
  var d = 0.0;
  for (var i = z.touch; i <= last; i++) {
    final x = ev.isBull ? (ev.edge - c.l[i]) / g : (c.h[i] - ev.edge) / g;
    if (x > d) d = x;
  }
  return d;
}
