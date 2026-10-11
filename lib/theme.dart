import 'package:flutter/material.dart';

/// Palette. Accents carry meaning only: green = profit/positive,
/// red = loss/negative, gold = selected item, replay cursor, active lines.
class C {
  C._();
  static const bg = Color(0xFF0E0F11);
  static const panel = Color(0xFF16181B);
  static const line = Color(0xFF24272B);
  static const lineHover = Color(0xFF33373C);
  static const rowLine = Color(0xFF1C1E21);
  static const text = Color(0xFFE8E9EB);
  static const mute = Color(0xFF7C8188);
  static const green = Color(0xFF3DDC84);
  static const red = Color(0xFFF05252);
  static const gold = Color(0xFFC9A54C);

  /// Strategy drawing palette only (SPEC §7.4: `amber`, `blue`); muted to sit with the rest.
  static const amber = Color(0xFFD9913D);
  static const blue = Color(0xFF5B8DD6);
}

const kFontFamily = 'Geist';

TextStyle ts(double size, {Color color = C.text, FontWeight w = FontWeight.w400, double? ls, double? height}) => TextStyle(
      fontFamily: kFontFamily,
      fontFamilyFallback: const ['Inter', 'Noto Sans', 'DejaVu Sans'],
      fontSize: size,
      color: color,
      fontWeight: w,
      letterSpacing: ls,
      height: height,
      decoration: TextDecoration.none,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

TextStyle capsLabel({Color color = C.mute}) => ts(11, color: color, ls: 0.9, w: FontWeight.w500);

ThemeData buildTheme() => ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: C.bg,
      fontFamily: kFontFamily,
      colorScheme: const ColorScheme.dark(primary: C.text, surface: C.panel, secondary: C.gold),
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      textSelectionTheme: TextSelectionThemeData(cursorColor: C.gold, selectionColor: C.gold.withOpacity(0.3)),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: C.line, borderRadius: BorderRadius.circular(8)),
        textStyle: ts(12),
        waitDuration: const Duration(milliseconds: 400),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(C.line),
        thickness: WidgetStateProperty.all(6),
        radius: const Radius.circular(999),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: C.panel,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: C.line)),
        textStyle: ts(13),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: C.panel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: C.line)),
      ),
    );

/// Material stand-ins for the Lucide set used in the design. Swap for
/// `lucide_icons_flutter` if you want exact glyphs.
class AppIcons {
  AppIcons._();
  static const data = Icons.storage_outlined;
  static const tools = Icons.layers_outlined;
  static const study = Icons.tune;
  static const expand = Icons.keyboard_double_arrow_right;
  static const collapse = Icons.keyboard_double_arrow_left;
  static const down = Icons.expand_more;
  static const up = Icons.expand_less;
  static const stats = Icons.view_sidebar_outlined;
  static const focus = Icons.center_focus_strong_outlined;
  static const play = Icons.play_arrow_rounded;
  static const pause = Icons.pause_rounded;
  static const toStart = Icons.skip_previous_rounded;
  static const stepBack = Icons.chevron_left;
  static const stepFwd = Icons.chevron_right;
  static const close = Icons.close;
  static const zoomIn = Icons.zoom_in;
  static const zoomOut = Icons.zoom_out;
  static const fit = Icons.fit_screen_outlined;
  static const volumeProfile = Icons.align_horizontal_left_rounded;
  static const selectBar = Icons.gps_fixed;
  static const calendar = Icons.calendar_today_outlined;
  static const replayEvent = Icons.history;
  static const upload = Icons.upload_outlined;
  static const plus = Icons.add;
  static const minus = Icons.remove;
  static const search = Icons.search;
  static const bull = Icons.north_east;
  static const bear = Icons.south_east;
  static const star = Icons.star_rounded;
  static const starOutline = Icons.star_border_rounded;
  static const export = Icons.file_download_outlined;
  static const clear = Icons.delete_outline;
  static const nextTouch = Icons.skip_next_rounded;
  static const drill = Icons.open_in_full;
  static const check = Icons.check;
  static const warn = Icons.error_outline;
  static const info = Icons.info_outline;
  static const tester = Icons.science_outlined;
  static const results = Icons.table_chart_outlined;
  static const history = Icons.history_toggle_off;
  static const build = Icons.construction_outlined;
  static const engine = Icons.memory_outlined;
  static const lock = Icons.lock_outline;
  static const unlock = Icons.lock_open_outlined;
  static const stop = Icons.stop_rounded;
  static const compare = Icons.compare_arrows;
  static const folder = Icons.folder_open_outlined;
  static const restart = Icons.restart_alt;
  static const tall = Icons.unfold_more;
  static const short = Icons.unfold_less;
  static const nextTrade = Icons.skip_next_rounded;
  static const indicators = Icons.stacked_line_chart;
}
