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
