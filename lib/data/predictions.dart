import 'events.dart';

class PredictionRecord {
  const PredictionRecord({
    required this.formationTime,
    required this.dir,
    required this.scenario,
    required this.sizeQ,
    required this.dispQ,
    required this.formationSession,
    required this.touchSession,
    required this.htfTrend,
    required this.ageBucket,
    required this.sweep,
    required this.period,
    required this.call,
    required this.actual,
    required this.correct,
    required this.answeredAt,
  });

  factory PredictionRecord.of(FvgEvent e, String call, DateTime at) => PredictionRecord(
        formationTime: e.time,
        dir: e.dirCode,
        scenario: e.scenario,
        sizeQ: e.sizeQ,
        dispQ: e.dispQ ?? '',
        formationSession: e.session,
        touchSession: e.touchSession ?? '',
        htfTrend: e.htfTrend ?? '',
        ageBucket: e.ageBucket ?? '',
        sweep: e.sweep == null ? '' : (e.sweep! ? 'yes' : 'no'),
        period: periodLabel(e.period),
        call: call,
        actual: e.outcome.name,
        correct: (call == 'bounce' && e.outcome == EvOutcome.bounce) || (call == 'break' && e.outcome == EvOutcome.through),
        answeredAt: at,
      );

  final String formationTime, dir, scenario, sizeQ;

  /// Conditions at the time of the call.
  final String dispQ, formationSession, touchSession, htfTrend, ageBucket, sweep, period;

  /// "bounce" | "break"
  final String call;

  /// "bounce" | "through" | "timeout" (from the events file)
  final String actual;
  final bool correct;
  final DateTime answeredAt;
}

String _q(Object v) {
  final s = '$v';
  return s.contains(',') || s.contains('"') ? '"${s.replaceAll('"', '""')}"' : s;
}

const _header = 'formation_time,dir,scenario,size_q,disp_q,formation_session,touch_session,htf_trend,age_bucket,sweep,period,'
    'call,actual,correct,answered_at';

String predictionsCsv(List<PredictionRecord> rows) {
  final b = StringBuffer('$_header\n');
  for (final r in rows) {
    b.writeln([
      r.formationTime, r.dir, r.scenario, r.sizeQ, r.dispQ, r.formationSession, r.touchSession, r.htfTrend,
      r.ageBucket, r.sweep, r.period, r.call, r.actual, r.correct, r.answeredAt.toUtc().toIso8601String(),
    ].map(_q).join(','));
  }
  return b.toString();
}
