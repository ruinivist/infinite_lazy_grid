import 'package:flutter/material.dart';
import 'dart:ui' as ui show FragmentProgram; // for runtime shader
import 'package:flutter/rendering.dart' show RendererBinding; // to mark repaint after async load

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

class DotGridBackground extends CanvasBackground {
  final double size; // radius in logical pixels at scale = 1
  final double spacing; // grid spacing in logical pixels at scale = 1
  final Color dotColor;
  final Color backgroundColor;

  // Static shader program cache shared across instances
  static ui.FragmentProgram? _program;
  static Future<ui.FragmentProgram>? _programFuture;

  const DotGridBackground({
    this.size = 2.0,
    this.spacing = 50.0,
    this.dotColor = Colors.black12,
    this.backgroundColor = Colors.white,
  }) : super();

  // Kick off async load once
  static void _ensureProgramLoaded() {
    if (_program != null || _programFuture != null) return;
    try {
      _programFuture = ui.FragmentProgram.fromAsset('packages/infinite_lazy_grid/shaders/dot_grid.frag')
        ..then((p) {
          _program = p;
          // Request a repaint when shader becomes available
          try {
            RendererBinding.instance.renderView.markNeedsPaint();
          } catch (_) {}
        }).catchError((_) {
          // keep _program null; we'll fallback to CPU/simple paint
        });
    } catch (_) {
      // fromAsset may throw synchronously on unsupported platforms
      _programFuture = null;
      _program = null;
    }
  }

  @override
  void paint(Canvas canvas, Offset screenOffset, Offset canvasOffset, double scale, Size canvasSize) {
    // Always draw background fill (also serves as fallback while shader loads)
    final bgPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.fill;
    final rect = Rect.fromLTWH(screenOffset.dx, screenOffset.dy, canvasSize.width, canvasSize.height);

    // Ensure shader load started
    _ensureProgramLoaded();

    final program = _program;
    if (program == null) {
      // Fallback: just fill background without dots until shader is ready
      canvas.drawRect(rect, bgPaint);
      return;
    }

    // Device pixel ratio for converting logical -> physical pixels used by FlutterFragCoord
    final dpr = RendererBinding.instance.renderView.configuration.devicePixelRatio;

    // Compute uniforms in physical pixels
    final scaledSpacingPx = (spacing * scale * dpr).abs();
    final radiusPx = (size * scale * dpr).abs();

    // Phase to align grid with world origin under pan/zoom
    double modPositive(double a, double m) => ((a % m) + m) % m;
    final phaseXPx = modPositive(canvasOffset.dx * scale * dpr, scaledSpacingPx == 0 ? 1 : scaledSpacingPx);
    final phaseYPx = modPositive(canvasOffset.dy * scale * dpr, scaledSpacingPx == 0 ? 1 : scaledSpacingPx);

    final originXPx = screenOffset.dx * dpr;
    final originYPx = screenOffset.dy * dpr;

    // Build fragment shader and set uniforms in declaration order
    final shader = program.fragmentShader();
    int i = 0;
    void set1(double a) {
      shader.setFloat(i++, a);
    }

    void set2(double a, double b) {
      shader.setFloat(i++, a);
      shader.setFloat(i++, b);
    }

    void set4c(Color c) {
      shader.setFloat(i++, c.r);
      shader.setFloat(i++, c.g);
      shader.setFloat(i++, c.b);
      shader.setFloat(i++, c.a);
    }

    set2(originXPx, originYPx);
    set1(scaledSpacingPx);
    set2(phaseXPx, phaseYPx);
    set1(radiusPx);
    set4c(dotColor);
    set4c(backgroundColor);

    final paint = Paint()..shader = shader;

    // Draw once with the shader
    canvas.drawRect(rect, paint);
  }
}
