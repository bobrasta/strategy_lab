const _mon = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _day = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String _p2(int v) => v.toString().padLeft(2, '0');

String fmtInt(int v) {
  final s = v.abs().toString(), b = StringBuffer(v < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

String fmtPrice(double p) {
  final parts = p.abs().toStringAsFixed(2).split('.');
  return '${p < 0 ? '-' : ''}${fmtInt(int.parse(parts[0]))}.${parts[1]}';
}

String fmtSigned(double v, {int digits = 2}) => '${v >= 0 ? '+' : ''}${v.toStringAsFixed(digits)}';

/// 2025-03-13 14:30
String fmtFull(DateTime t) => '${t.year}-${_p2(t.month)}-${_p2(t.day)} ${_p2(t.hour)}:${_p2(t.minute)}';

/// 13 Mar 14:30
String fmtShort(DateTime t) => '${t.day} ${_mon[t.month - 1]} ${_p2(t.hour)}:${_p2(t.minute)}';

/// Thu 13 Mar 2025 · 14:30
String fmtDock(DateTime t) => '${_day[t.weekday - 1]} ${t.day} ${_mon[t.month - 1]} ${t.year} · ${_p2(t.hour)}:${_p2(t.minute)}';

/// Axis tick: date at midnight, time otherwise.
String fmtAxis(DateTime t) => t.hour == 0 && t.minute == 0 ? '${t.day} ${_mon[t.month - 1]}' : '${_p2(t.hour)}:${_p2(t.minute)}';

/// Splits "58.3%" into ("58", ".3%") so the decimals can be dimmed.
(String, String) splitDecimal(String s) {
  final i = s.indexOf('.');
  return i < 0 ? (s, '') : (s.substring(0, i), s.substring(i));
}

/// Money for display, from an engine value: -1,234.56 (rounded for display only).
String fmtMoney(double? v) {
  if (v == null || v.isNaN) return '—';
  final r = v.toStringAsFixed(2);
  final neg = r.startsWith('-') && r != '-0.00';
  final parts = (neg ? r.substring(1) : r.replaceFirst('-', '')).split('.');
  return '${neg ? '-' : ''}${fmtInt(int.parse(parts[0]))}.${parts[1]}';
}

/// Signed money: +1,234.56 / -1,234.56.
String fmtMoneySigned(double? v) => v == null || v.isNaN ? '—' : '${v > 0 ? '+' : ''}${fmtMoney(v)}';

/// A plain engine number for display with [d] decimals ("—" for null / NaN / infinite).
String fmtNum(Object? v, [int d = 2]) {
  if (v is! num || v.isNaN || v.isInfinite) return '—';
  return v.toDouble().toStringAsFixed(d);
}

/// 283786 s → "3 d 6 h", 5400 s → "1 h 30 m".
String fmtDuration(double? seconds) {
  if (seconds == null || seconds.isNaN) return '—';
  final s = seconds.round(), d = s ~/ 86400, h = s % 86400 ~/ 3600, m = s % 3600 ~/ 60;
  if (d > 0) return '$d d $h h';
  if (h > 0) return '$h h $m m';
  return '$m m ${s % 60} s';
}

/// 2025-03-13 (date part of a UTC instant).
String fmtDate(int ms) => fmtFull(DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true)).substring(0, 10);
