import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../run/protection.dart';

const kDefaultEngineRepo = '/home/bob/projects/hummer-engine';
const kDefaultDataFile = '/home/bob/Documents/fxdata/xauusd_m1_2021-01-01_2026-10-08.csv';

/// Cost overrides offered in the tester, as `hummer run` options (SPEC §8, CLI).
const kCostOptions = ['costs', 'spread', 'commission', 'slippage', 'seed', 'swap_mode', 'swap_long', 'swap_short', 'triple_swap_day'];

/// An indicator attached to the chart (SPEC §14 M7): its name, the inputs the user set (the rest
/// use the indicator's defaults) and whether it is shown. The list order is the drawing order.
class IndicatorSetting {
  IndicatorSetting(this.name, Map<String, String> inputs, {this.visible = true}) : inputs = Map.unmodifiable(inputs);
  final String name;
  final Map<String, String> inputs;
  final bool visible;

  Map<String, dynamic> toJson() => {'name': name, 'inputs': inputs, 'visible': visible};

  static IndicatorSetting? fromJson(Object? j) {
    if (j is! Map || j['name'] is! String || (j['name'] as String).isEmpty) return null;
    final inp = j['inputs'];
    return IndicatorSetting(j['name'] as String, {if (inp is Map) for (final e in inp.entries) '${e.key}': '${e.value}'}, visible: j['visible'] != false);
  }
}

/// Everything remembered between sessions, in the app support folder (settings.json).
/// Saves are debounced; a failed save is reported once and never blocks the app.
class Settings {
  Settings(this.file);

  final File? file;
  String engineRepo = kDefaultEngineRepo;

  /// Empty: `<engineRepo>/build/release/hummer`, where the release preset puts it.
  String engineBinary = '';
  String dataFile = kDefaultDataFile;
  String from = '', to = '';
  String tickPath = 'nearest', ambiguity = 'path';
  String deposit = '', leverage = '';
  String? lastStrategy;

  /// Input values per strategy (only the ones the user set; the rest use the strategy's defaults).
  final Map<String, Map<String, String>> inputs = {};

  /// Cost overrides (option → value); absent = the profile's value.
  final Map<String, String> costs = {};

  /// Per-strategy protected period. A key mapped to null means the user removed the protection.
  final Map<String, ProtectedPeriod?> protectedPeriods = {};

  /// Runs ticked for comparison and the run last opened (restored after a restart).
  String? lastRunDir;

  /// The data file shown on the chart without a run (Indicators → Open chart), restored when no
  /// run is. Null while a run is open.
  String? chartDataFile;

  /// Indicators attached to the chart, recomputed (cache hits) at startup.
  List<IndicatorSetting> indicators = [];

  String get binary => engineBinary.isNotEmpty ? engineBinary : '$engineRepo/build/release/hummer';
  String get runsDir => '$engineRepo/runs';
  String get profilePath => '$engineRepo/profiles/xauusd.json';

  ProtectedPeriod? protectionFor(String strategy) =>
      protectedPeriods.containsKey(strategy) ? protectedPeriods[strategy] : kDefaultProtection[strategy];

  Timer? _save;
  String? saveError;

  static Future<Settings> load(File? file) async {
    final s = Settings(file);
    if (file == null || !await file.exists()) return s;
    try {
      final j = jsonDecode(await file.readAsString());
      if (j is Map) s._apply(j.cast<String, dynamic>());
    } catch (_) {
      // A damaged settings file starts from the defaults; the next save replaces it.
    }
    return s;
  }

  void _apply(Map<String, dynamic> j) {
    String str(String k, String d) => j[k] is String ? j[k] as String : d;
    engineRepo = str('engine_repo', engineRepo);
    engineBinary = str('engine_binary', engineBinary);
    dataFile = str('data_file', dataFile);
    from = str('from', from);
    to = str('to', to);
    tickPath = str('tick_path', tickPath);
    ambiguity = str('ambiguity', ambiguity);
    deposit = str('deposit', deposit);
    leverage = str('leverage', leverage);
    lastStrategy = j['last_strategy'] as String?;
    lastRunDir = j['last_run'] as String?;
    chartDataFile = j['chart_data_file'] is String ? j['chart_data_file'] as String : null;
    final ind = j['indicators'];
    if (ind is List) indicators = [for (final x in ind) ?IndicatorSetting.fromJson(x)];
    final inp = j['inputs'];
    if (inp is Map) {
      for (final e in inp.entries) {
        if (e.value is Map) inputs['${e.key}'] = {for (final x in (e.value as Map).entries) '${x.key}': '${x.value}'};
      }
    }
    final c = j['costs'];
    if (c is Map) {
      for (final e in c.entries) {
        if (kCostOptions.contains(e.key) && '${e.value}'.isNotEmpty) costs['${e.key}'] = '${e.value}';
      }
    }
    final p = j['protected_periods'];
    if (p is Map) {
      for (final e in p.entries) {
        protectedPeriods['${e.key}'] = ProtectedPeriod.fromJson(e.value);
      }
    }
  }

  Map<String, dynamic> toJson() => {
        'engine_repo': engineRepo,
        'engine_binary': engineBinary,
        'data_file': dataFile,
        'from': from,
        'to': to,
        'tick_path': tickPath,
        'ambiguity': ambiguity,
        'deposit': deposit,
        'leverage': leverage,
        'last_strategy': lastStrategy,
        'last_run': lastRunDir,
        'chart_data_file': chartDataFile,
        'indicators': [for (final i in indicators) i.toJson()],
        'inputs': inputs,
        'costs': costs,
        'protected_periods': {for (final e in protectedPeriods.entries) e.key: e.value?.toJson()},
      };

  /// Schedules a save (coalesced over 300 ms).
  void changed() {
    _save?.cancel();
    _save = Timer(const Duration(milliseconds: 300), flush);
  }

  Future<void> flush() async {
    _save?.cancel();
    _save = null;
    final f = file;
    if (f == null) return;
    try {
      await f.parent.create(recursive: true);
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(const JsonEncoder.withIndent('  ').convert(toJson()), flush: true);
      await tmp.rename(f.path);
      saveError = null;
    } catch (e) {
      saveError = "Settings couldn't be saved: $e";
    }
  }
}
