import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/lab_screen.dart';
import 'state/app_state.dart';
import 'theme.dart';

/// Run with `flutter run -d linux --dart-define=PRESET=3` to open a demo state on
/// the bundled sample data: 1 explore · 2 explore + drawers · 3 replay ·
/// 4 replay predict · 5 empty (default; load your own files).
void main() {
  const preset = int.fromEnvironment('PRESET', defaultValue: 5);
  runApp(FvgLabApp(state: AppState()..applyPreset(preset)));
}

class FvgLabApp extends StatefulWidget {
  const FvgLabApp({super.key, required this.state});
  final AppState state;

  @override
  State<FvgLabApp> createState() => _FvgLabAppState();
}

class _FvgLabAppState extends State<FvgLabApp> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    widget.state.dispose();
    super.dispose();
  }

  bool _typing() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    return ctx != null && (ctx.widget is EditableText || ctx.findAncestorWidgetOfExactType<EditableText>() != null);
  }

  bool _onKey(KeyEvent e) {
    if (_typing()) return false;
    final s = widget.state;
    final down = e is KeyDownEvent, repeat = e is KeyRepeatEvent;
    final k = e.logicalKey;
    final kb = HardwareKeyboard.instance;
    if (down && k == LogicalKeyboardKey.keyF && !kb.isControlPressed && !kb.isMetaPressed) {
      s.toggleFocus();
      return true;
    }
    if (down && k == LogicalKeyboardKey.escape) {
      s.escape();
      return true;
    }
    if (!s.isReplay) return false;
    if (down && k == LogicalKeyboardKey.space) {
      s.togglePlay();
      return true;
    }
    if ((down || repeat) && k == LogicalKeyboardKey.arrowRight) {
      kb.isShiftPressed ? s.nextEvent() : s.step(1);
      return true;
    }
    if ((down || repeat) && k == LogicalKeyboardKey.arrowLeft) {
      s.step(-1);
      return true;
    }
    if (down && k == LogicalKeyboardKey.keyN) {
      s.nextTouch();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'FVG Lab',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: LabScreen(state: widget.state),
      );
}
