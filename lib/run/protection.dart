import 'dart:convert';
import 'dart:io';

/// Written into a run's folder when its protected-period overlap was confirmed.
const kConfirmationFile = 'protected_period_confirmation.json';

/// A strategy's hold-out: dates from [from] (inclusive, UTC) up to [to] (inclusive; null = open-ended).
class ProtectedPeriod {
  const ProtectedPeriod(this.from, [this.to]);

  /// YYYY-MM-DD.
  final String from;
  final String? to;

  int get fromMs => DateTime.parse('${from}T00:00:00Z').millisecondsSinceEpoch;

  /// End of [to]'s day, exclusive; null when open-ended.
  int? get toMsExcl => to == null ? null : DateTime.parse('${to}T00:00:00Z').add(const Duration(days: 1)).millisecondsSinceEpoch;

  /// Whether the span [a, b] (ms, inclusive; null = unbounded) touches this period.
  bool overlaps(int? a, int? b) {
    final pe = toMsExcl;
    final startsBeforeEnd = pe == null || a == null || a < pe;
    final endsAfterStart = b == null || b >= fromMs;
    return startsBeforeEnd && endsAfterStart;
  }

  String get label => to == null ? '$from onwards' : '$from to $to';

  Map<String, dynamic> toJson() => {'from': from, 'to': to};

  static ProtectedPeriod? fromJson(Object? j) {
    if (j is! Map) return null;
    final f = j['from'], t = j['to'];
    if (f is! String || !isIsoDate(f)) return null;
    return ProtectedPeriod(f, t is String && isIsoDate(t) ? t : null);
  }

  @override
  bool operator ==(Object other) => other is ProtectedPeriod && other.from == from && other.to == to;
  @override
  int get hashCode => Object.hash(from, to);
}

bool isIsoDate(String s) => RegExp(r'^\d{4}-\d\d-\d\d$').hasMatch(s) && DateTime.tryParse('${s}T00:00:00Z') != null;

/// Protected by default until the user changes it (hard rule: FVG continuation runs on 2021–2023 only).
const kDefaultProtection = {'fvg_continuation': ProtectedPeriod('2024-01-01'), 'builtin:practice': ProtectedPeriod('2024-01-01')};

/// A logged confirmation (the file in the run's folder).
class Confirmation {
  const Confirmation({required this.confirmedAt, required this.kind, required this.period, required this.strategy});

  /// UTC, from the wall clock at the moment of the click.
  final DateTime confirmedAt;

  /// "start" (confirmed before the run) or "reveal" (an existing run's results unlocked).
  final String kind;
  final ProtectedPeriod period;
  final String strategy;

  static Confirmation? fromJson(Object? j) {
    if (j is! Map) return null;
    final at = DateTime.tryParse('${j['confirmed_at']}');
    final p = ProtectedPeriod.fromJson(j['protected_period']);
    if (at == null || p == null) return null;
    return Confirmation(confirmedAt: at.toUtc(), kind: '${j['kind'] ?? 'start'}', period: p, strategy: '${j['strategy'] ?? ''}');
  }

  /// A confirmation covers a period only if it was for that same period (changing the period asks again).
  bool covers(ProtectedPeriod p) => period == p;
}

Confirmation? readConfirmation(String dir) {
  final f = File('$dir${Platform.pathSeparator}$kConfirmationFile');
  if (!f.existsSync()) return null;
  try {
    return Confirmation.fromJson(jsonDecode(f.readAsStringSync()));
  } catch (_) {
    return null;
  }
}

/// Logs the confirmation with a timestamp in the run's folder (created if the worker hasn't yet).
Future<Confirmation> writeConfirmation(
  String dir, {
  required String kind,
  required String strategy,
  required ProtectedPeriod period,
  required String? runFrom,
  required String? runTo,
  DateTime? now,
}) async {
  final at = (now ?? DateTime.now()).toUtc();
  await Directory(dir).create(recursive: true);
  final body = {
    'confirmed_at': at.toIso8601String(),
    'kind': kind,
    'strategy': strategy,
    'protected_period': period.toJson(),
    'run_from': runFrom,
    'run_to': runTo,
    'note': kind == 'start'
        ? 'The user confirmed starting a run that overlaps this protected period.'
        : 'The user confirmed revealing the results of this run, which overlaps this protected period.',
  };
  await File('$dir${Platform.pathSeparator}$kConfirmationFile').writeAsString('${const JsonEncoder.withIndent('  ').convert(body)}\n', flush: true);
  return Confirmation(confirmedAt: at, kind: kind, period: period, strategy: strategy);
}
