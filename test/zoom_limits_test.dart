// Verifies controller zoom bounds and viewport transforms.
// Exercises the public API and canvas input routes.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_lazy_grid/infinite_lazy_grid.dart';

// ---------- Helpers ----------

Future<void> pumpCanvas(
  WidgetTester tester,
  LazyCanvasController controller,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 300,
          height: 200,
          child: LazyCanvas(controller: controller),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void expectOffset(Offset actual, Offset expected) {
  expect(actual.dx, closeTo(expected.dx, 1e-7));
  expect(actual.dy, closeTo(expected.dy, 1e-7));
}

// ---------- Zoom limits ----------

void main() {
  test('validates bounds and clamps the initial scale', () {
    for (final invalid in [
      0.0,
      -1.0,
      double.nan,
      double.infinity,
      -double.infinity,
    ]) {
      expect(
        () => LazyCanvasController(minScale: invalid),
        throwsArgumentError,
      );
      expect(
        () => LazyCanvasController(maxScale: invalid),
        throwsArgumentError,
      );
    }
    expect(
      () => LazyCanvasController(minScale: 2, maxScale: 1),
      throwsArgumentError,
    );
    final controllers = [
      LazyCanvasController(),
      LazyCanvasController(minScale: 2),
      LazyCanvasController(maxScale: 0.5),
      LazyCanvasController(minScale: 2, maxScale: 2),
    ];
    expect(controllers.map((c) => c.scale), [1, 2, 0.5, 2]);
    expect(controllers.first.minScale, isNull);
    expect(controllers.first.maxScale, isNull);
    expect(controllers.last.minScale, 2);
    expect(controllers.last.maxScale, 2);
    for (final controller in controllers) {
      controller.dispose();
    }
  });

  testWidgets('additive zoom preserves the focal point at both bounds', (
    tester,
  ) async {
    for (final bounds in [
      (null, null),
      (0.5, null),
      (null, 2.0),
      (0.5, 2.0),
      (1.0, 1.0),
    ]) {
      final controller = LazyCanvasController(
        minScale: bounds.$1,
        maxScale: bounds.$2,
      );
      await pumpCanvas(tester, controller);
      const focalPoint = Offset(90, 60);
      for (final requested in [10.0, 15.0, 0.1]) {
        final gridPoint = controller.offset + focalPoint / controller.scale;
        controller.updateScalebyDelta(
          requested - controller.scale,
          focalPoint: focalPoint,
        );
        expect(
          controller.scale,
          closeTo(
            requested.clamp(bounds.$1 ?? 0.0, bounds.$2 ?? double.infinity),
            1e-7,
          ),
        );
        expectOffset(
          (gridPoint - controller.offset) * controller.scale,
          focalPoint,
        );
      }
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    }
  });

  testWidgets('pinch clamps scale while panning continues at a limit', (
    tester,
  ) async {
    final controller = LazyCanvasController(minScale: 0.5, maxScale: 2);
    await pumpCanvas(tester, controller);
    const focalPoint = Offset(90, 60);
    controller.onScaleStart(ScaleStartDetails(focalPoint: focalPoint));
    for (final ratio in [10.0, 0.1]) {
      final gridPoint = controller.offset + focalPoint / controller.scale;
      controller.onScaleUpdate(
        ScaleUpdateDetails(focalPoint: focalPoint, scale: ratio),
      );
      expect(controller.scale, ratio.clamp(0.5, 2));
      expectOffset(
        (gridPoint - controller.offset) * controller.scale,
        focalPoint,
      );
    }
    final beforePan = controller.offset;
    const delta = Offset(20, 10);
    controller.onScaleUpdate(
      ScaleUpdateDetails(
        focalPoint: focalPoint + delta,
        focalPointDelta: delta,
        scale: 0.1,
      ),
    );
    expect(controller.scale, 0.5);
    expectOffset(controller.offset, beforePan - delta / 0.5);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('releasing a clamped pinch does not start inertia', (
    tester,
  ) async {
    for (final bounds in [(null, 1.0, 2.0), (1.0, null, 0.5)]) {
      final controller = LazyCanvasController(
        minScale: bounds.$1,
        maxScale: bounds.$2,
      );
      await pumpCanvas(tester, controller);
      controller.onScaleStart(
        ScaleStartDetails(focalPoint: const Offset(90, 60), pointerCount: 2),
      );
      controller.onScaleUpdate(
        ScaleUpdateDetails(
          focalPoint: const Offset(110, 60),
          focalPointDelta: const Offset(20, 0),
          scale: bounds.$3,
          pointerCount: 2,
        ),
      );
      expect(controller.scale, 1);
      expect(controller.offset, const Offset(-20, 0));
      controller.onScaleUpdate(
        ScaleUpdateDetails(focalPoint: const Offset(110, 60), pointerCount: 2),
      );
      final beforeRelease = controller.offset;
      controller.onScaleEnd(
        ScaleEndDetails(
          velocity: const Velocity(pixelsPerSecond: Offset(1000, 0)),
        ),
      );
      await tester.pumpAndSettle();
      expect(controller.offset, beforeRelease);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    }
  });

  testWidgets('wheel and trackpad zoom use the controller limits', (
    tester,
  ) async {
    final controller = LazyCanvasController(minScale: 0.95, maxScale: 1.05);
    await pumpCanvas(tester, controller);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    for (final dy in [-400.0, 400.0]) {
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: const Offset(90, 60),
          scrollDelta: Offset(0, dy),
        ),
      );
      expect(controller.scale, dy < 0 ? 1.05 : 0.95);
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    for (final ratio in [4.0, 0.1]) {
      await tester.sendEventToBinding(
        PointerScaleEvent(position: const Offset(90, 60), scale: ratio),
      );
      expect(controller.scale, ratio > 1 ? 1.05 : 0.95);
    }
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('focus centers using bounded reset and fit scales', (
    tester,
  ) async {
    for (final bounds in [(2.0, 3.0), (0.25, 0.5)]) {
      final controller = LazyCanvasController(
        minScale: bounds.$1,
        maxScale: bounds.$2,
      );
      final id = controller.addChild(
        const Offset(500, 600),
        const SizedBox(),
        childSize: const Size(100, 100),
      );
      await pumpCanvas(tester, controller);
      for (final animate in [false, true]) {
        for (final size in [const Size(1000, 1000), const Size(10, 10)]) {
          for (final mode in [
            ScalingMode.resetScale,
            ScalingMode.fitInViewport,
          ]) {
            controller.focusOnChild(
              id,
              childSize: size,
              scalingMode: mode,
              animate: animate,
            );
            await tester.pumpAndSettle();
            final requested = mode == ScalingMode.resetScale
                ? 1.0
                : 200 / size.height;
            expect(controller.scale, requested.clamp(bounds.$1, bounds.$2));
            final gridCenter =
                const Offset(500, 600) + size.center(Offset.zero);
            expectOffset(
              (gridCenter - controller.offset) * controller.scale,
              const Offset(150, 100),
            );
          }
        }
      }
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    }
  });

  testWidgets('animations clamp targets and overshooting intermediate scales', (
    tester,
  ) async {
    final controller = LazyCanvasController(minScale: 0.5, maxScale: 2);
    await pumpCanvas(tester, controller);
    for (final target in [10.0, 0.1]) {
      final seen = <double>[];
      void recordScale() => seen.add(controller.scale);
      controller.addListener(recordScale);
      final transition = controller.animateToOffsetAndScale(
        offset: const Offset(400, 300),
        scale: target,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutBack,
      );
      await tester.pump();
      for (var frame = 0; frame < 20; frame++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      await tester.pumpAndSettle();
      await transition;
      controller.removeListener(recordScale);
      expect(seen.length, greaterThan(2));
      expect(seen, everyElement(inInclusiveRange(0.5, 2)));
      expect(controller.scale, target.clamp(0.5, 2));
      expect(controller.offset, const Offset(400, 300));
    }
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
