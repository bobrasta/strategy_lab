import 'dart:typed_data';

/// Byte-level parsers for the engine's and the downloader's CSV files. They avoid a String per
/// field on the hot path (2M-row files) and give exactly what `double.parse` / `DateTime.utc` give.

/// Days since 1970-01-01 for a proleptic Gregorian date (H. Hinnant's days_from_civil).
int daysFromCivil(int y, int m, int d) {
  y -= m <= 2 ? 1 : 0;
  final era = (y >= 0 ? y : y - 399) ~/ 400;
  final yoe = y - era * 400;
  final doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) ~/ 5 + d - 1;
  final doe = yoe * 365 + yoe ~/ 4 - yoe ~/ 100 + doy;
  return era * 146097 + doe - 719468;
}

int _d2(Uint8List b, int i) => (b[i] - 48) * 10 + b[i + 1] - 48;

bool _digits(Uint8List b, int s, int n) {
  for (var i = s; i < s + n; i++) {
    final c = b[i];
    if (c < 48 || c > 57) return false;
  }
  return true;
}

/// `YYYY-MM-DD HH:MM:SS` or `YYYY-MM-DD HH:MM` (UTC) in b[s, e) → ms since epoch, else null.
int? parseTimeBytes(Uint8List b, int s, int e) {
  final n = e - s;
  if ((n != 19 && n != 16) || b[s + 4] != 45 || b[s + 7] != 45 || b[s + 10] != 32 || b[s + 13] != 58) return null;
  if (!_digits(b, s, 4) || !_digits(b, s + 5, 2) || !_digits(b, s + 8, 2) || !_digits(b, s + 11, 2) || !_digits(b, s + 14, 2)) return null;
  var sec = 0;
  if (n == 19) {
    if (b[s + 16] != 58 || !_digits(b, s + 17, 2)) return null;
    sec = _d2(b, s + 17);
  }
  final y = _d2(b, s) * 100 + _d2(b, s + 2), mo = _d2(b, s + 5), d = _d2(b, s + 8), h = _d2(b, s + 11), mi = _d2(b, s + 14);
  if (mo < 1 || mo > 12 || d < 1 || d > 31 || h > 23 || mi > 59 || sec > 59) return null;
  return ((daysFromCivil(y, mo, d) * 24 + h) * 60 + mi) * 60000 + sec * 1000;
}

const _pow10 = [1e0, 1e1, 1e2, 1e3, 1e4, 1e5, 1e6, 1e7, 1e8, 1e9, 1e10, 1e11, 1e12, 1e13, 1e14, 1e15, 1e16, 1e17, 1e18, 1e19, 1e20, 1e21, 1e22];

/// Decimal number in b[s, e) → double, bit-identical to `double.parse`; null if not a number.
/// Fast path (Clinger): at most 15 significant digits and no exponent, so the digits form an exact
/// double and one division by an exact power of ten is correctly rounded. Everything else
/// (17-digit shortest round-trip output, exponents, nan) goes through `double.parse`.
double? parseDoubleBytes(Uint8List b, int s, int e) {
  if (s >= e) return null;
  var i = s;
  var neg = false;
  if (b[i] == 45) {
    neg = true;
    i++;
  } else if (b[i] == 43) {
    i++;
  }
  var mant = 0, digits = 0, frac = -1;
  var ok = i < e, any = false;
  for (; i < e; i++) {
    final c = b[i];
    if (c >= 48 && c <= 57) {
      any = true;
      if (digits > 0 || c != 48) digits++;
      mant = mant * 10 + (c - 48);
      if (frac >= 0) frac++;
      if (digits > 15) {
        ok = false;
        break;
      }
    } else if (c == 46 && frac < 0) {
      frac = 0;
    } else {
      ok = false;
      break;
    }
  }
  if (ok && any && frac <= 22) {
    final v = frac > 0 ? mant / _pow10[frac] : mant.toDouble();
    return neg ? -v : v;
  }
  return double.tryParse(String.fromCharCodes(b, s, e));
}

/// Like [parseDoubleBytes] but for plotting only: up to 18 significant digits are kept and the
/// result can differ from `double.parse` by a few ulp. Never use it for numbers shown as text.
double? parseDoubleApprox(Uint8List b, int s, int e) {
  if (s >= e) return null;
  var i = s;
  var neg = false;
  if (b[i] == 45) {
    neg = true;
    i++;
  }
  var mant = 0, digits = 0, frac = -1, dropped = 0;
  var any = false;
  for (; i < e; i++) {
    final c = b[i];
    if (c >= 48 && c <= 57) {
      any = true;
      if (digits < 18) {
        if (digits > 0 || c != 48) digits++;
        mant = mant * 10 + (c - 48);
        if (frac >= 0) frac++;
      } else if (frac < 0) {
        dropped++;
      }
    } else if (c == 46 && frac < 0) {
      frac = 0;
    } else {
      return parseDoubleBytes(b, s, e); // exponent or junk: the exact path
    }
  }
  if (!any) return null;
  final exp = dropped - (frac > 0 ? frac : 0);
  final v = exp >= 0 ? mant * _pow10[exp.clamp(0, 22)] : mant / _pow10[(-exp).clamp(0, 22)];
  return neg ? -v : v;
}

/// Reusable comma positions of one line, so a 2M-line file is parsed without per-line allocation.
class CsvLine {
  CsvLine([int maxFields = 64]) : _ends = Int32List(maxFields);
  final Int32List _ends;
  int _start = 0, _n = 0;

  /// Splits b[s, e) at commas (e is the newline position; a trailing CR is dropped).
  void split(Uint8List b, int s, int e) {
    if (e > s && b[e - 1] == 13) e--;
    _start = s;
    _n = 0;
    for (var i = s; i < e; i++) {
      if (b[i] == 44 && _n < _ends.length - 1) _ends[_n++] = i;
    }
    _ends[_n++] = e;
  }

  int get count => _n;
  int start(int k) => k == 0 ? _start : _ends[k - 1] + 1;
  int end(int k) => _ends[k];
}

/// Trims spaces and one pair of surrounding quotes from b[s, e); returns the new bounds via [out].
void trimField(Uint8List b, int s, int e, Int32List out) {
  while (s < e && (b[s] == 32 || b[s] == 9)) {
    s++;
  }
  while (e > s && (b[e - 1] == 32 || b[e - 1] == 9)) {
    e--;
  }
  if (e - s >= 2 && b[s] == 34 && b[e - 1] == 34) {
    s++;
    e--;
  }
  out[0] = s;
  out[1] = e;
}
