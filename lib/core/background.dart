import 'package:flutter/material.dart';
import './render.dart';

/// Abstract definition for a [LazyCanvas] background.
abstract class CanvasBackground {
  /// the fill color of background
  final Color bgColor;
  const CanvasBackground({this.bgColor = Colors.white});

  /// draw the backround on this context. Implement this to have
  /// different kinds of backgrounds
  /// [screenOffset] is the screen space offset for clipping
  /// [canvasOffset] is the grid space offset from the controller
  void paint(Canvas canvas, Offset screenOffset, Offset canvasOffset, double scale, Size canvasSize);
}

class NoBackground extends CanvasBackground {
  const NoBackground();

  @override
  void paint(Canvas canvas, Offset screenOffset, Offset canvasOffset, double scale, Size canvasSize) {}
}

class SingleColorBackround extends CanvasBackground {
  const SingleColorBackround(Color backgroundColor) : super(bgColor: backgroundColor);

  @override
  void paint(Canvas canvas, Offset screenOffset, Offset canvasOffset, double scale, Size canvasSize) {
    final paint = Paint()
      ..color = bgColor
      ..style = PaintingStyle.fill;

    canvas.drawRect(Rect.fromLTWH(screenOffset.dx, screenOffset.dy, canvasSize.width, canvasSize.height), paint);
  }
}

class DotGridBackround extends CanvasBackground {
  final double size;
  final double spacing;
  final Color color;

  const DotGridBackround({this.size = 2.0, this.spacing = 50.0, this.color = Colors.black12}) : super();

  @override
  void paint(Canvas canvas, Offset screenOffset, Offset canvasOffset, double scale, Size canvasSize) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0 * scale;
    double scaledSpacing = spacing * scale;
    double scaledSize = size * scale;

    // Use canvasOffset to determine the grid position in grid space
    // Calculate the grid origin in canvas space (0,0 should be at a grid point)
    // Find the first grid point that aligns with the coordinate system
    double firstGridX = (canvasOffset.dx / spacing).floor() * spacing;
    double firstGridY = (canvasOffset.dy / spacing).floor() * spacing;

    // Convert grid space coordinates to screen space
    double screenStartX = (firstGridX - canvasOffset.dx) * scale + screenOffset.dx;
    double screenStartY = (firstGridY - canvasOffset.dy) * scale + screenOffset.dy;

    // Ensure we start drawing before the visible area to avoid gaps
    while (screenStartX > screenOffset.dx) {
      screenStartX -= scaledSpacing;
    }
    while (screenStartY > screenOffset.dy) {
      screenStartY -= scaledSpacing;
    }

    for (double x = screenStartX; x < screenOffset.dx + canvasSize.width + scaledSpacing; x += scaledSpacing) {
      for (double y = screenStartY; y < screenOffset.dy + canvasSize.height + scaledSpacing; y += scaledSpacing) {
        canvas.drawCircle(Offset(x, y), scaledSize, paint);
      }
    }
  }
}
