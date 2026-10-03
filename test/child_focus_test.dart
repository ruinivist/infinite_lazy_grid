// Verifies child fitting, centering and cached measurements.
// Exercises viewport transitions through the public controller API.
import 'package:flutter/material.dart';
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

void expectCentered(LazyCanvasController controller, CanvasChildId id) {
  final info = controller.getInfo(id);
  final center =
      info.ssPosition + info.childSize!.center(Offset.zero) * controller.scale;
  expect(center.dx, closeTo(150, 1e-7));
  expect(center.dy, closeTo(100, 1e-7));
}

// ---------- Focus behavior ----------

void main() {
  testWidgets('fits the limiting dimension and respects horizontal margin', (
    tester,
  ) async {
    final controller = LazyCanvasController();
    final id = controller.addChild(
      const Offset(500, 600),
      const SizedBox(width: 100, height: 160),
      childSize: const Size(100, 160),
    );
    await pumpCanvas(tester, controller);
    controller.updateScalebyDelta(1, focalPoint: Offset.zero);
    controller.focusOnChild(
      id,
      scalingMode: ScalingMode.fitInViewport,
      animate: false,
    );
    expect(controller.scale, closeTo(1.25, 1e-7));
    expectCentered(controller, id);
    controller.update(
      id,
      childSize: const Size(100, 40),
      widget: const SizedBox(width: 100, height: 40),
    );
    controller.focusOnChild(
      id,
      scalingMode: ScalingMode.fitInViewport,
      preferredHorizontalMargin: 20,
      animate: false,
    );
    expect(controller.scale, closeTo(2.6, 1e-7));
    expect(controller.getInfo(id).ssPosition.dx, closeTo(20, 1e-7));
    expectCentered(controller, id);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('keep and reset scale center even oversized screen bounds', (
    tester,
  ) async {
    final controller = LazyCanvasController();
    final id = controller.addChild(
      const Offset(500, 600),
      const SizedBox(width: 180, height: 60),
      childSize: const Size(180, 60),
    );
    await pumpCanvas(tester, controller);
    controller.updateScalebyDelta(1, focalPoint: Offset.zero);
    controller.focusOnChild(id, animate: false);
    expect(controller.scale, 2);
    expectCentered(controller, id);
    expect(controller.getInfo(id).ssPosition.dx, closeTo(-30, 1e-7));
    controller.focusOnChild(
      id,
      scalingMode: ScalingMode.resetScale,
      animate: false,
    );
    expect(controller.scale, 1);
    expectCentered(controller, id);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('animated fitting ends at the same centered transform', (
    tester,
  ) async {
    final controller = LazyCanvasController();
    final id = controller.addChild(
      const Offset(500, 600),
      const SizedBox(width: 100, height: 160),
      childSize: const Size(100, 160),
    );
    await pumpCanvas(tester, controller);
    controller.focusOnChild(
      id,
      scalingMode: ScalingMode.fitInViewport,
      duration: const Duration(milliseconds: 100),
    );
    await tester.pumpAndSettle();
    expect(controller.scale, closeTo(1.25, 1e-7));
    expectCentered(controller, id);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('focus reuses measured and explicit sizes while culled', (
    tester,
  ) async {
    final controller = LazyCanvasController();
    var builds = 0;
    final id = controller.addChild(
      const Offset(20, 20),
      Builder(
        builder: (_) {
          builds++;
          return const SizedBox(width: 80, height: 40);
        },
      ),
    );
    await pumpCanvas(tester, controller);
    expect(builds, 1);
    controller.scrollBy(const Offset(800, 0));
    await tester.pumpAndSettle();
    expect(controller.widgetsWithScreenPositions(), isEmpty);
    controller.focusOnChild(id);
    expect(controller.getInfo(id).childSize, const Size(80, 40));
    expect(builds, 1);
    controller.focusOnChild(id);
    expect(builds, 1);
    controller.focusOnChild(id, childSize: const Size(100, 60), animate: false);
    expect(controller.getInfo(id).childSize, const Size(100, 60));
    controller.focusOnChild(id, animate: false);
    expectCentered(controller, id);
    expect(builds, 1);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('zero dimensions fit without producing an invalid scale', (
    tester,
  ) async {
    final controller = LazyCanvasController();
    final id = controller.addChild(const Offset(500, 600), const SizedBox());
    await pumpCanvas(tester, controller);
    for (final size in [const Size(0, 100), const Size(100, 0), Size.zero]) {
      controller.focusOnChild(
        id,
        childSize: size,
        scalingMode: ScalingMode.fitInViewport,
        animate: false,
      );
      expect(controller.scale.isFinite, isTrue);
      expect(controller.scale, greaterThan(0));
      expect(controller.getInfo(id).childSize, size);
      expectCentered(controller, id);
    }
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
