// Time inputs of indicator programs, read and written as the engine does.

/// The engine's fixed range volume profile indicator (`indicators/volume_profile.cpp`).
const kVolumeProfile = 'volume_profile';

String _p2(int v) => v.toString().padLeft(2, '0');

/// `YYYY.MM.DD HH:MI` (UTC): the indicator's RangeFrom / RangeTo input format (MQL5 StringToTime).
String fmtInputTime(int ms) {
  final t = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  return '${t.year}.${_p2(t.month)}.${_p2(t.day)} ${_p2(t.hour)}:${_p2(t.minute)}';
}

final _timeRe = RegExp(r'^(\d{4})([.-])(\d{1,2})\2(\d{1,2})(?:(?:T| +)(\d{1,2}):(\d{1,2})(?::(\d{1,2}))?)?$');

/// Reads a time input as the engine's StringToTime does (SPEC §7.7, `hm::Program::StringToTime`):
/// `YYYY.MM.DD [HH:MI[:SS]]` or `YYYY-MM-DD [HH:MM[:SS]]`, date and time separated by spaces or one
/// `T`, UTC. Null where the engine would read 0 (not a time).
int? parseInputTime(String? text) {
  final m = _timeRe.firstMatch((text ?? '').trim());
  if (m == null) return null;
  int g(int i) => int.parse(m.group(i) ?? '0');
  final y = g(1), mo = g(3), d = g(4), h = g(5), mi = g(6), s = g(7);
  if (y < 1970 || mo < 1 || mo > 12 || d < 1 || h > 23 || mi > 59 || s > 59) return null;
  final t = DateTime.utc(y, mo, d, h, mi, s);
  if (t.month != mo || t.day != d) return null; // 31 April, 29 February of a common year
  return t.millisecondsSinceEpoch;
}
