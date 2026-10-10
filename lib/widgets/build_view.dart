import 'package:flutter/material.dart';

import '../state/lab_state.dart';
import '../theme.dart';
import 'common.dart';

/// Compiler output of the last strategy build (from build_output events) and of Build engine.
class BuildView extends StatefulWidget {
  const BuildView({super.key, required this.lab});
  final LabState lab;
  @override
  State<BuildView> createState() => _BuildViewState();
}

class _BuildViewState extends State<BuildView> {
  final _scroll = ScrollController();
  int _lastLen = -1;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lab = widget.lab, b = lab.build;
    final engineLines = lab.engineBuildLines;
    final showEngine = lab.engineBuilding || (engineLines.isNotEmpty && (b == null || lab.engineBuildResult != null));
    final lines = showEngine ? engineLines : (b?.lines ?? const <String>[]);
    if (lines.length != _lastLen) {
      _lastLen = lines.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
    }
    final String title;
    final Color color;
    if (showEngine) {
      title = lab.engineBuilding ? 'Building the engine (cmake --preset release && cmake --build --preset release)…' : (lab.engineBuildResult ?? '');
      color = lab.engineBuilding ? C.text : ((lab.engineBuildResult ?? '').contains('OK') ? C.green : C.red);
    } else if (b == null) {
      title = 'No build yet. Choose a strategy in the Tester and press Build.';
      color = C.mute;
    } else {
      title = switch (b.status) {
        'running' => 'Building ${b.name}…',
        'ok' => 'BUILD OK ${b.name}.so${b.seconds == null ? '' : ' (${b.seconds!.toStringAsFixed(1)} s)'}',
        'stopped' => 'Build of ${b.name} stopped',
        _ => 'BUILD FAILED ${b.name}',
      };
      color = switch (b.status) { 'ok' => C.green, 'running' => C.text, 'stopped' => C.mute, _ => C.red };
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
        height: 40,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(children: [
            if ((b?.running ?? false) || lab.engineBuilding) ...[
              const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, color: C.mute)),
              const SizedBox(width: 10),
            ],
            Expanded(child: Text(title, overflow: TextOverflow.ellipsis, style: ts(12, color: color, w: FontWeight.w500))),
            if (!showEngine && (b?.running ?? false)) PillButton(label: 'Stop build', icon: AppIcons.stop, height: 28, fontSize: 12, onTap: lab.stopBuild),
          ]),
        ),
      ),
      Expanded(
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: C.bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: C.line)),
          child: SelectionArea(
            child: ListView.builder(
              controller: _scroll,
              itemCount: lines.length,
              itemBuilder: (_, i) {
                final l = lines[i];
                final err = l.contains('error') || l.startsWith('BUILD FAILED');
                final warn = !err && l.contains('warning');
                return Text(l, style: ts(11.5, color: err ? C.red : (warn ? C.gold : C.text), height: 1.35).copyWith(fontFamily: 'monospace', fontFamilyFallback: const ['DejaVu Sans Mono']));
              },
            ),
          ),
        ),
      ),
    ]);
  }
}
