import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'screens/lab_screen.dart';
import 'state/app_state.dart';
import 'state/lab_state.dart';
import 'state/settings.dart';
import 'theme.dart';

/// Strategy Lab: starts `hummer serve`, runs backtests through it and replays their output files.
/// Settings live in the app support folder (settings.json); the parsed-candle cache in the cache folder.
/// `--dart-define=SETTINGS_DIR=<dir>` keeps settings.json there instead (tests, a second profile).
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final lab = await createLab();
  runApp(StrategyLabApp(lab: lab));
  await lab.init();
}

Future<LabState> createLab({String? settingsDir}) async {
  const override = String.fromEnvironment('SETTINGS_DIR');
  final dir = settingsDir ?? (override.isNotEmpty ? override : (await getApplicationSupportDirectory()).path);
  final cache = await getApplicationCacheDirectory();
  final settings = await Settings.load(File('$dir${Platform.pathSeparator}settings.json'));
  return LabState(chart: AppState(), settings: settings, cacheDir: cache.path);
}

class StrategyLabApp extends StatefulWidget {
  const StrategyLabApp({super.key, required this.lab, this.manageEngine = true});
  final LabState lab;

  /// Tests that drive the app with a fake engine set this to false.
  final bool manageEngine;

  @override
  State<StrategyLabApp> createState() => _StrategyLabAppState();
}

class _StrategyLabAppState extends State<StrategyLabApp> {
  late final AppLifecycleListener _life;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    // Window close: shutdown to the engine, up to 2 s, then kill (its workers die with it).
    _life = AppLifecycleListener(onExitRequested: () async {
      if (widget.manageEngine) await widget.lab.shutdown();
      return AppExitResponse.exit;
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _life.dispose();
    super.dispose();
  }

  bool _typing() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    return ctx != null && (ctx.widget is EditableText || ctx.findAncestorWidgetOfExactType<EditableText>() != null);
  }

  bool _onKey(KeyEvent e) {
    if (_typing()) return false;
    final s = widget.lab.chart;
    final down = e is KeyDownEvent, repeat = e is KeyRepeatEvent;
    final k = e.logicalKey;
    final kb = HardwareKeyboard.instance;
    if (down && k == LogicalKeyboardKey.keyF && !kb.isControlPressed && !kb.isMetaPressed) {
      s.toggleFocus();
      return true;
    }
    if (down && k == LogicalKeyboardKey.escape) {
      if (widget.lab.vpTool.cancel()) return true;
      if (widget.lab.compare != null) {
        widget.lab.closeCompare();
      } else {
        s.escape();
      }
      return true;
    }
    if (down && (k == LogicalKeyboardKey.delete || k == LogicalKeyboardKey.backspace) && widget.lab.vpTool.deleteSelected()) {
      return true;
    }
    if (!s.isReplay) return false;
    if (down && k == LogicalKeyboardKey.space) {
      s.togglePlay();
      return true;
    }
    if ((down || repeat) && k == LogicalKeyboardKey.arrowRight) {
      kb.isShiftPressed ? s.nextTrade() : s.step(1);
      return true;
    }
    if ((down || repeat) && k == LogicalKeyboardKey.arrowLeft) {
      s.step(-1);
      return true;
    }
    if (down && k == LogicalKeyboardKey.keyN) {
      s.nextTrade();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Strategy Lab',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: LabScreen(lab: widget.lab),
      );
}
