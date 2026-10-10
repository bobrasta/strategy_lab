import 'equity_store.dart';
import 'run_data.dart';

/// A chart object as of some moment (drawings.jsonl replayed up to it).
class DrawObj {
  DrawObj(this.name, this.kind, this.color, this.label, this.shape);
  final String name, kind, color, label;
  final String? shape;
  int t1 = 0;
  double p1 = 0, p2 = 0;

  /// null = OPEN_END: extends to "now".
  int? t2;
}

/// An opened run: its files, its equity store, and lookups at a moment [ms] that never read
/// anything stamped after [ms] (the replay rule).
class RunView {
  RunView(this.data, this.equity, {this.equityError});

  final RunData data;
  final EquityStore? equity;
  final String? equityError;

  RunManifest get manifest => data.manifest;
  List<Trade> get trades => data.trades;

  late final Map<int, Trade> _byTicket = {for (final t in data.trades) t.ticket: t};
  Trade? tradeByTicket(int ticket) => _byTicket[ticket];

  static int _upper(int n, int Function(int) msAt, int ms) {
    var lo = 0, hi = n;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (msAt(mid) <= ms) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// Trades opened at or before [ms] (trades are in open order).
  int tradesOpenedBy(int ms) => _upper(trades.length, (i) => trades[i].openMs, ms);
  int dealsBy(int ms) => _upper(data.deals.length, (i) => data.deals[i].ms, ms);
  int journalBy(int ms) => _upper(data.journal.length, (i) => data.journal[i].ms, ms);

  /// The position open at [ms] (one position at a time), or null when flat.
  Trade? positionAt(int ms) {
    final k = tradesOpenedBy(ms);
    if (k == 0) return null;
    final t = trades[k - 1];
    return t.closeMs > ms ? t : null;
  }

  EquityRow? equityAt(int ms) => equity?.at(ms);

  // Drawing state, advanced incrementally as the cursor moves forward.
  final Map<String, DrawObj> _objs = {};
  int _applied = 0, _stateMs = -1 << 62;

  /// Objects as of [ms]: only events stamped at or before it are applied.
  Iterable<DrawObj> drawingsAt(int ms) {
    if (ms < _stateMs) {
      _objs.clear();
      _applied = 0;
    }
    _stateMs = ms;
    final ev = data.drawings;
    while (_applied < ev.length && ev[_applied].ms <= ms) {
      _apply(ev[_applied++]);
    }
    return _objs.values;
  }

  void _apply(DrawEvent e) {
    final j = e.j;
    switch (e.op) {
      case 'delete':
        _objs.remove(e.name);
        return;
      case 'create':
        _objs[e.name] = DrawObj(e.name, '${j['kind']}', '${j['color'] ?? 'mute'}', '${j['label'] ?? ''}', j['shape'] as String?);
    }
    final o = _objs[e.name];
    if (o == null) return;
    o.t1 = engineMs(j['t1']) ?? o.t1;
    o.p1 = (j['p1'] as num?)?.toDouble() ?? o.p1;
    if (j.containsKey('t2')) o.t2 = engineMs(j['t2']);
    o.p2 = (j['p2'] as num?)?.toDouble() ?? o.p2;
  }

  void dispose() => equity?.close();
}
