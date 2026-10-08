import 'dart:convert';
import 'dart:io';

String siblingPath(String path, String name) => '${File(path).parent.path}${Platform.pathSeparator}$name';

double? _d(Object? v) => v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);

class BaselinePoint {
  const BaselinePoint(this.d, this.real, this.fake, this.z);
  final double d;
  final double? real, fake, z;
}

class BaselineBySize {
  const BaselineBySize(this.dir, this.sizeQ, this.real, this.fake, this.z);
  final String dir, sizeQ;
  final double? real, fake, z;
}

/// fvg_baseline_summary.json written by the Python study (real vs random zones).
class Baseline {
  const Baseline({this.realBounceRate, this.fakeBounceRate, this.diffPp, this.z, this.curve = const [], this.bySize = const []});
  final double? realBounceRate, fakeBounceRate, diffPp, z;
  final List<BaselinePoint> curve;
  final List<BaselineBySize> bySize;

  factory Baseline.fromJson(Map<String, dynamic> j) {
    final real = _d(j['real_bounce_rate']), fake = _d(j['fake_bounce_rate']);
    return Baseline(
      realBounceRate: real,
      fakeBounceRate: fake,
      diffPp: _d(j['diff_pp']) ?? (real != null && fake != null ? (real - fake) * 100 : null),
      z: _d(j['z']),
      curve: [
        for (final m in (j['curve'] as List? ?? const []).whereType<Map>()) BaselinePoint(_d(m['d']) ?? 0, _d(m['real']), _d(m['fake']), _d(m['z'])),
      ],
      bySize: [
        for (final m in (j['by_size'] as List? ?? const []).whereType<Map>())
          BaselineBySize('${m['dir']}', '${m['size_q']}', _d(m['real']), _d(m['fake']), _d(m['z'])),
      ],
    );
  }
}

/// |z| ≥ 3 significant, |z| ≥ 2 weak.
String significance(double z) => z.abs() >= 3
    ? 'significant'
    : z.abs() >= 2
        ? 'weak'
        : 'not significant';

/// Loads fvg_baseline_summary.json from the events file's folder, or null if absent.
Future<Baseline?> loadBaselineNextTo(String eventsPath) async {
  final f = File(siblingPath(eventsPath, 'fvg_baseline_summary.json'));
  if (!await f.exists()) return null;
  final j = jsonDecode(await f.readAsString());
  if (j is! Map<String, dynamic>) throw const FormatException('expected a JSON object');
  return Baseline.fromJson(j);
}
