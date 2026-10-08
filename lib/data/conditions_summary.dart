import 'dart:convert';
import 'dart:io';

import 'baseline.dart' show siblingPath;
import 'events.dart';
import 'stats.dart';

double? _d(Object? v) => v is num ? v.toDouble() : null;
int _i(Object? v) => v is num ? v.toInt() : 0;

/// One bucket of fvg_conditions_summary.json (written by fvg_conditions.py) in one period.
class SummaryRow {
  const SummaryRow({
    required this.period,
    required this.feature,
    required this.bucket,
    required this.nReal,
    required this.nFake,
    required this.nControlReal,
    required this.nControlFake,
    required this.real,
    required this.fake,
    required this.diffPp,
    required this.z,
    required this.controlDiffPp,
    required this.controlZ,
    required this.verdict,
  });

  final Period period;

  /// Python column (`disp_q`, `trend`, `age_b`, `touch_session`, `form_session`, `sweep_b`) or `all`.
  final String feature, bucket;

  /// Resolved (non-timeout) events per group.
  final int nReal, nFake, nControlReal, nControlFake;
  final double? real, fake, diffPp, z, controlDiffPp, controlZ;

  /// candidate | artifact | no_edge | needs_data
  final String verdict;
}

class ConditionsSummary {
  const ConditionsSummary(this.rows);
  final List<SummaryRow> rows;

  factory ConditionsSummary.fromJson(Map<String, dynamic> j) {
    final rows = <SummaryRow>[];
    final periods = j['periods'];
    if (periods is Map) {
      periods.forEach((k, v) {
        final p = parsePeriod('$k');
        if (p == null || v is! List) return;
        for (final m in v.whereType<Map>()) {
          rows.add(SummaryRow(
            period: p,
            feature: '${m['feature']}',
            bucket: '${m['bucket']}',
            nReal: _i(m['n_real']),
            nFake: _i(m['n_fake']),
            nControlReal: _i(m['n_control_real']),
            nControlFake: _i(m['n_control_fake']),
            real: _d(m['real']),
            fake: _d(m['fake']),
            diffPp: _d(m['diff_pp']),
            z: _d(m['z']),
            controlDiffPp: _d(m['control_diff_pp']),
            controlZ: _d(m['control_z']),
            verdict: '${m['verdict']}',
          ));
        }
      });
    }
    return ConditionsSummary(rows);
  }

  SummaryRow? find(Period p, String feature, String bucket) {
    for (final r in rows) {
      if (r.period == p && r.feature == feature && r.bucket == bucket) return r;
    }
    return null;
  }

  /// Loads fvg_conditions_summary.json from the events file's folder, or null if absent.
  static Future<ConditionsSummary?> loadNextTo(String eventsPath) async {
    final f = File(siblingPath(eventsPath, 'fvg_conditions_summary.json'));
    if (!await f.exists()) return null;
    final j = jsonDecode(await f.readAsString());
    if (j is! Map<String, dynamic>) throw const FormatException('expected a JSON object');
    return ConditionsSummary.fromJson(j);
  }
}

/// The app-side test for one JSON bucket, or null for a feature the app doesn't know.
/// The bucket label is normalised once, not per event.
bool Function(FvgEvent)? bucketTest(String feature, String bucket) {
  switch (feature) {
    case 'all':
      return (_) => true;
    case 'disp_q':
      final v = normalizeDisp(bucket);
      return (e) => v != null && e.dispQ == v;
    case 'trend':
      final v = normalizeTrend(bucket);
      return (e) => v != null && e.htfTrend == v;
    case 'age_b':
      final v = normalizeAge(bucket);
      return (e) => v != null && e.ageBucket == v;
    case 'touch_session':
      final v = normalizeSession(bucket);
      return (e) => v != null && e.touchSession == v;
    case 'form_session':
      final v = normalizeSession(bucket);
      return (e) => v != null && e.session == v;
    case 'sweep_b':
      final v = parseBool(bucket);
      return (e) => v != null && e.sweep == v;
  }
  return null;
}

String verdictCode(Verdict v) => switch (v) {
      Verdict.candidate => 'candidate',
      Verdict.artifact => 'artifact',
      Verdict.noEdge => 'no_edge',
      Verdict.needsData => 'needs_data',
    };

/// The comparison the app shows for one JSON bucket, built from the per-event files.
Comparison? comparisonFor(SummaryRow r, List<FvgEvent> real, List<FvgEvent> fake, List<FvgEvent> control) {
  final t = bucketTest(r.feature, r.bucket);
  if (t == null) return null;
  bool m(FvgEvent e) => e.period == r.period && t(e);
  return Comparison(
    rateOf(real.where(m)),
    rateOf(fake.where(m)),
    rateOf(control.where((e) => e.kind == 'real' && m(e))),
    rateOf(control.where((e) => e.kind == 'fake' && m(e))),
  );
}

/// Whether the app's numbers for one JSON bucket match the study's.
bool rowMatches(SummaryRow r, List<FvgEvent> real, List<FvgEvent> fake, List<FvgEvent> control) {
  final c = comparisonFor(r, real, fake, control);
  if (c == null) return true; // a feature the app doesn't filter on
  bool near(double? a, double? b) => (a == null && b == null) || (a != null && b != null && (a - b).abs() < 1e-9);
  return c.real.resolved == r.nReal &&
      c.fake!.resolved == r.nFake &&
      c.controlReal!.resolved == r.nControlReal &&
      c.controlFake!.resolved == r.nControlFake &&
      near(c.real.rate, r.real) &&
      near(c.fake!.rate, r.fake) &&
      verdictCode(c.verdict) == r.verdict;
}

String rowLabel(SummaryRow r) => '${periodLabel(r.period)} ${r.feature}=${r.bucket}';

/// Buckets where the app's numbers differ from the study's JSON (stale or mismatched files).
List<String> crossCheck(ConditionsSummary s, List<FvgEvent> real, List<FvgEvent> fake, List<FvgEvent> control) =>
    [for (final r in s.rows) if (!rowMatches(r, real, fake, control)) rowLabel(r)];
