import 'package:flutter/material.dart';
import 'dart:ui' as ui show FragmentProgram; // for runtime shader
import 'package:flutter/rendering.dart'
    show RendererBinding; // to mark repaint after async load

/// Abstract definition for a [LazyCanvas] background.
abstract class CanvasBackground {
  /// the fill color of background
  final Color bgColor;
  const CanvasBackground({this.bgColor = Colors.white});

  /// draw the backround on this context. Implement this to have
  /// different kinds of backgrounds
  /// [screenOffset] is the screen space offset for clipping
  /// [canvasOffset] is the grid space offset from the controller
  void paint(
    Canvas canvas,
    Offset screenOffset,
    Offset canvasOffset,
    double scale,
    Size canvasSize,
  );
}

class NoBackground extends CanvasBackground {
  const NoBackground();

  @override
  void paint(
    Canvas canvas,
    Offset screenOffset,
    Offset canvasOffset,
    double scale,
    Size canvasSize,
  ) {}
}

class SingleColorBackground extends CanvasBackground {
  const SingleColorBackground(Color backgroundColor)
    : super(bgColor: backgroundColor);

  @override
  void paint(
    Canvas canvas,
    Offset screenOffset,
    Offset canvasOffset,
    double scale,
    Size canvasSize,
  ) {
    final paint = Paint()
      ..color = bgColor
      ..style = PaintingStyle.fill;

    canvas.drawRect(
      Rect.fromLTWH(
        screenOffset.dx,
        screenOffset.dy,
        canvasSize.width,
        canvasSize.height,
      ),
      paint,
    );
  }
}

class DotGridBackground extends CanvasBackground {
  final double size; // radius in logical pixels at scale = 1
  final double spacing; // grid spacing in logical pixels at scale = 1
  final Color dotColor;
  final Color backgroundColor;
  // Allow choosing pan semantics: true => grid moves with content ("natural"), false => inverted
  final bool naturalPan;

  // Static shader program cache shared across instances
  static ui.FragmentProgram? _program;
  static Future<ui.FragmentProgram>? _programFuture;

  const DotGridBackground({
    this.size = 2.0,
    this.spacing = 50.0,
    this.dotColor = Colors.black12,
    this.backgroundColor = Colors.white,
    this.naturalPan = true,
  }) : super();

  // Kick off async load once
  static void _ensureProgramLoaded() {
    if (_program != null || _programFuture != null) return;
    try {
      _programFuture =
          ui.FragmentProgram.fromAsset(
              'packages/infinite_lazy_grid/shaders/dot_grid.frag',
            )
            ..then((p) {
              _program = p;
              // Request a repaint when shader becomes available
              try {
                for (final renderView in RendererBinding.instance.renderViews) {
                  renderView.markNeedsPaint();
                }
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
  void paint(
    Canvas canvas,
    Offset screenOffset,
    Offset canvasOffset,
    double scale,
    Size canvasSize,
  ) {
    // Always draw background fill (also serves as fallback while shader loads)
    final bgPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.fill;
    final rect = Rect.fromLTWH(
      screenOffset.dx,
      screenOffset.dy,
      canvasSize.width,
      canvasSize.height,
    );

    // Ensure shader load started
    _ensureProgramLoaded();

    final program = _program;
    if (program == null) {
      // Fallback: just fill background without dots until shader is ready
      canvas.drawRect(rect, bgPaint);
      return;
    }

    // Compute uniforms in logical pixels to match FlutterFragCoord and CPU path
    final scaledSpacingPx = (spacing * scale).abs();
    final radiusPx = (size * scale).abs();

    // Phase to align grid with world origin under pan/zoom
    double modPositive(double a, double m) => ((a % m) + m) % m;
    final sign = naturalPan ? 1.0 : -1.0;
    final phaseXPx = modPositive(
      sign * canvasOffset.dx * scale,
      scaledSpacingPx == 0 ? 1 : scaledSpacingPx,
    );
    final phaseYPx = modPositive(
      sign * canvasOffset.dy * scale,
      scaledSpacingPx == 0 ? 1 : scaledSpacingPx,
    );

    // Snap origin: use exact logical origin (no rounding) to match CPU path
    final originXPx = screenOffset.dx;
    final originYPx = screenOffset.dy;

    // Precompute inverse spacing to avoid division in shader
    final invScaledSpacing = scaledSpacingPx == 0 ? 0.0 : 1.0 / scaledSpacingPx;

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
    set1(invScaledSpacing);
    set2(phaseXPx, phaseYPx);
    set1(radiusPx);
    set4c(dotColor);
    set4c(backgroundColor);

    final paint = Paint()..shader = shader;

    // Draw once with the shader
    canvas.drawRect(rect, paint);
  }
}

class DotGridBackgroundCpu extends CanvasBackground {
  final double size; // radius in logical pixels at scale = 1
  final double spacing; // grid spacing in logical pixels at scale = 1
  final Color dotColor;
  final Color backgroundColor;
  // true => grid tracks content ("natural"), false => inverted pan
  final bool naturalPan;

  const DotGridBackgroundCpu({
    this.size = 2.0,
    this.spacing = 50.0,
    this.dotColor = Colors.black12,
    this.backgroundColor = Colors.white,
    this.naturalPan = true,
  }) : super();

  @override
  void paint(
    Canvas canvas,
    Offset screenOffset,
    Offset canvasOffset,
    double scale,
    Size canvasSize,
  ) {
    // Fill background
    final rect = Rect.fromLTWH(
      screenOffset.dx,
      screenOffset.dy,
      canvasSize.width,
      canvasSize.height,
    );
    final bgPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.fill;
    canvas.drawRect(rect, bgPaint);

    // Early out if dots are too dense or too small
    final spacingSS = (spacing * scale).abs();
    final radiusSS = (size * scale).abs();
    if (spacingSS < 1.0 || radiusSS < 0.25) {
      return; // background already drawn
    }

    final dotPaint = Paint()
      ..color = dotColor
      ..style = PaintingStyle.fill;

    // Choose pan semantics
    final sign = naturalPan ? 1.0 : -1.0;

    // Determine visible grid-space bounds to iterate
    // Screen rect spans [screenOffset, screenOffset + canvasSize]
    // xSS = screenOffset.x + (xGS - sign*canvasOffset.x) * scale
    // Solve for xGS bounds to cover the screen rect (+radius margin)
    final marginGSX = radiusSS / scale;
    final marginGSY = radiusSS / scale;

    final xGsMin = sign * canvasOffset.dx - marginGSX;
    final xGsMax =
        sign * canvasOffset.dx + (canvasSize.width + 2 * radiusSS) / scale;
    final yGsMin = sign * canvasOffset.dy - marginGSY;
    final yGsMax =
        sign * canvasOffset.dy + (canvasSize.height + 2 * radiusSS) / scale;

    int nStartX = (xGsMin / spacing).floor();
    int nEndX = (xGsMax / spacing).ceil();
    int nStartY = (yGsMin / spacing).floor();
    int nEndY = (yGsMax / spacing).ceil();

    // Iterate grid and draw circles
    for (int nx = nStartX; nx <= nEndX; nx++) {
      final xGS = nx * spacing;
      final xSS = screenOffset.dx + (xGS - sign * canvasOffset.dx) * scale;
      if (xSS + radiusSS < rect.left || xSS - radiusSS > rect.right)
        continue; // skip out-of-bounds columns

      for (int ny = nStartY; ny <= nEndY; ny++) {
        final yGS = ny * spacing;
        final ySS = screenOffset.dy + (yGS - sign * canvasOffset.dy) * scale;
        if (ySS + radiusSS < rect.top || ySS - radiusSS > rect.bottom)
          continue; // skip out-of-bounds rows

        canvas.drawCircle(Offset(xSS, ySS), radiusSS, dotPaint);
      }
    }
  }
}
