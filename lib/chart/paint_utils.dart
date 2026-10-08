import 'dart:math';

import 'package:flutter/painting.dart';

void dashH(Canvas c, double x0, double x1, double y, Paint p, {double dash = 4, double gap = 3}) {
  for (var x = x0; x < x1; x += dash + gap) {
    c.drawLine(Offset(x, y), Offset(min(x + dash, x1), y), p);
  }
}

void dashV(Canvas c, double x, double y0, double y1, Paint p, {double dash = 4, double gap = 3}) {
  for (var y = y0; y < y1; y += dash + gap) {
    c.drawLine(Offset(x, y), Offset(x, min(y + dash, y1)), p);
  }
}

/// Draws text vertically centred on [at.dy].
void drawText(Canvas c, String text, Offset at, TextStyle style, {TextAlign align = TextAlign.left}) {
  final tp = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr)..layout();
  var dx = at.dx;
  if (align == TextAlign.center) {
    dx -= tp.width / 2;
  } else if (align == TextAlign.right) {
    dx -= tp.width;
  }
  tp.paint(c, Offset(dx, at.dy - tp.height / 2));
}

void tag(Canvas c, Rect r, String text, Color bg, Color fg, TextStyle style) {
  c.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(6)), Paint()..color = bg);
  drawText(c, text, r.center, style.copyWith(color: fg), align: TextAlign.center);
}
