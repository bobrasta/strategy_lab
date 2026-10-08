import 'package:backy/main.dart';
import 'package:backy/state/app_state.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  for (final size in const [Size(1440, 900), Size(1920, 1037)]) {
    testWidgets('demo presets render without errors at ${size.width.toInt()}×${size.height.toInt()}', (t) async {
      await loadFallbackFont();
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      for (final p in [1, 2, 3, 4, 5]) {
        final s = AppState()..applyPreset(p);
        await t.pumpWidget(FvgLabApp(key: ValueKey(p), state: s));
        await t.pump(const Duration(milliseconds: 50));
        expect(t.takeException(), isNull, reason: 'preset $p');
        if (p == 4) expect(find.text('NEXT BAR TOUCHES THE GAP · YOUR CALL'), findsOneWidget);
        if (p == 5) expect(find.textContaining('Load XAUUSD candles'), findsOneWidget);
        s.toggleLeft(true);
        s.toggleRight();
        await t.pump();
        expect(t.takeException(), isNull, reason: 'preset $p with rail + stats open');
      }
      await t.pumpWidget(const SizedBox());
    });
  }
}
