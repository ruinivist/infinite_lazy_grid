import 'package:flutter/material.dart';
import './render.dart';

/// Abstract definition for a [LazyCanvas] background.
abstract class CanvasBackground {
  /// the fill color of background
  final Color bgColor;
  const CanvasBackground({this.bgColor = Colors.white});

  /// draw the backround on this context. Implement this to have
  /// different kinds of backgrounds
  void paint(Canvas canvas, Size canvasSize, double scale);
}

class NoBackground extends CanvasBackground {
  const NoBackground();

  @override
  void paint(Canvas canvas, Size canvasSize, double scale) {}
}

class SingleColorBackround extends CanvasBackground {
  const SingleColorBackround(Color backgroundColor) : super(bgColor: backgroundColor);

  @override
  void paint(Canvas canvas, Size canvasSize, double scale) {
    final paint = Paint()
      ..color = bgColor
      ..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 0, canvasSize.width, canvasSize.height), paint);
  }
}
