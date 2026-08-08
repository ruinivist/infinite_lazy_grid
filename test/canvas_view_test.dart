import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:infinite_lazy_grid/infinite_lazy_grid.dart';

class TestChild extends StatelessWidget {
  final int index;
  const TestChild({required this.index, super.key});
  @override
  Widget build(BuildContext context) {
    return SizedBox(key: ValueKey('test_child_$index'), width: 50, height: 50);
  }
}

class TestBackground extends CanvasBackground {
  final _repaint = ValueNotifier(0);

  @override
  Listenable get repaint => _repaint;
  int paintCount = 0;

  void notify() => _repaint.value++;

  @override
  void paint(
    Canvas canvas,
    Offset screenOffset,
    Offset canvasOffset,
    double scale,
    Size canvasSize,
  ) {
    paintCount++;
  }
}

Future<void> _pumpCanvas(
  WidgetTester tester,
  LazyCanvasController controller,
) async {
  await tester.pumpWidget(
    MaterialApp(home: LazyCanvas(controller: controller)),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('repaints when the background becomes ready', (tester) async {
    final background = TestBackground();
    final controller = LazyCanvasController(background: background);
    await _pumpCanvas(tester, controller);
    final initialPaintCount = background.paintCount;

    background.notify();
    await tester.pump();

    expect(background.paintCount, greaterThan(initialPaintCount));
  });

  testWidgets(
    'CanvasView renders only visible children and reduces count on zoom out',
    (WidgetTester tester) async {
      final controller = LazyCanvasController(debug: true);
      for (int i = 0; i < 10000; i++) {
        controller.addChild(
          Offset((i % 80) * 100.0, (i ~/ 80) * 100.0),
          TestChild(index: i),
        );
      }
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: LazyCanvas(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();

      final initialChildren = find.byType(TestChild);
      final initialCount = tester.widgetList(initialChildren).length;

      // should be less than 10000 children rendered (only those part of the visible viewport)
      expect(initialCount, lessThan(10000));
      expect(initialCount, greaterThan(0));

      controller.updateScalebyDelta(1); // 2x zoom in
      await tester.pumpAndSettle();

      // After zooming out, fewer children should be visible
      final afterZoomChildren = find.byType(TestChild);
      final afterZoomCount = tester.widgetList(afterZoomChildren).length;
      expect(afterZoomCount, lessThan(initialCount));
      expect(afterZoomCount, greaterThan(0));
    },
  );

  testWidgets('CanvasView scales as expected', (WidgetTester tester) async {
    final controller = LazyCanvasController(debug: true);
    controller.addChild(const Offset(0, 0), TestChild(index: 0));
    controller.addChild(const Offset(100, 100), TestChild(index: 1));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: LazyCanvas(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();

    // Initial size check
    final finder = find.byType(TestChild);
    expect(finder, findsNWidgets(2));

    // Simulate a scale update to 2x, keeping the top-left at (0,0)
    controller.onScaleStart(ScaleStartDetails(focalPoint: const Offset(0, 0)));
    controller.onScaleUpdate(
      ScaleUpdateDetails(focalPoint: const Offset(0, 0), scale: 2.0),
    );
    await tester.pumpAndSettle();
    expect(controller.scale, 2.0);
    final ssPositions = controller
        .widgetsWithScreenPositions()
        .map((e) => e.ssPosition)
        .toList();
    expect(ssPositions, [Offset.zero, const Offset(200, 200)]);
  });

  testWidgets('renders children at the same position', (
    WidgetTester tester,
  ) async {
    final controller = LazyCanvasController();
    final firstId = controller.addChild(Offset.zero, const TestChild(index: 0));
    controller.addChild(Offset.zero, const TestChild(index: 1));

    await _pumpCanvas(tester, controller);

    expect(find.byType(TestChild), findsNWidgets(2));

    controller.removeChild(firstId);
    await tester.pump();

    expect(find.byType(TestChild), findsOneWidget);
  });

  testWidgets('brings a child to the front', (WidgetTester tester) async {
    final controller = LazyCanvasController();
    var tapped = -1;
    final firstId = controller.addChild(
      Offset.zero,
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => tapped = 0,
        child: const SizedBox(width: 50, height: 50),
      ),
    );
    final secondId = controller.addChild(
      Offset.zero,
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => tapped = 1,
        child: const SizedBox(width: 50, height: 50),
      ),
    );
    await _pumpCanvas(tester, controller);

    await tester.tapAt(const Offset(10, 10));
    expect(tapped, 1);

    controller.bringToFront(firstId);
    await tester.pump();
    expect(controller.widgetsWithScreenPositions().map((child) => child.id), [
      secondId,
      firstId,
    ]);

    await tester.tapAt(const Offset(10, 10));
    expect(tapped, 0);
  });

  testWidgets('stops rendering a child moved outside the viewport', (
    WidgetTester tester,
  ) async {
    final controller = LazyCanvasController(
      buildCacheExtent: Offset.zero,
      hashCellSize: const Size(10, 10),
    );
    final id = controller.addChild(Offset.zero, const TestChild(index: 0));
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 200,
            height: 200,
            child: LazyCanvas(controller: controller),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    controller.updatePosition(id, const Offset(500, 0));
    await tester.pump();

    expect(find.byType(TestChild), findsNothing);
  });

  testWidgets('build cache extent scales beyond each edge', (
    WidgetTester tester,
  ) async {
    final controller = LazyCanvasController(
      buildCacheExtent: const Offset(50, 50),
      hashCellSize: const Size(10, 10),
    );
    controller.addChild(const Offset(150, 0), TestChild(index: 0));

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 200,
            height: 200,
            child: LazyCanvas(controller: controller),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    controller.updateScalebyDelta(1, focalPoint: Offset.zero);
    await tester.pumpAndSettle();

    expect(find.byType(TestChild), findsOneWidget);
  });

  testWidgets('keeps a partially visible scaled child mounted', (
    WidgetTester tester,
  ) async {
    final controller = LazyCanvasController(
      buildCacheExtent: const Offset(50, 50),
      hashCellSize: const Size(10, 10),
    );
    controller.addChild(Offset.zero, const TestChild(index: 0));

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 200,
            height: 200,
            child: LazyCanvas(controller: controller),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    controller.onScaleStart(ScaleStartDetails(focalPoint: Offset.zero));
    controller.onScaleUpdate(
      ScaleUpdateDetails(
        focalPoint: Offset.zero,
        focalPointDelta: const Offset(0, -40),
      ),
    );
    controller.updateScalebyDelta(1, focalPoint: Offset.zero);
    await tester.pumpAndSettle();

    expect(controller.scale, 2);
    expect(controller.widgetsWithScreenPositions().single.ssPosition.dy, -80);
    expect(find.byType(TestChild), findsOneWidget);
  });

  testWidgets('continues a pan with inertia at the current scale', (
    WidgetTester tester,
  ) async {
    final controller = LazyCanvasController();
    await _pumpCanvas(tester, controller);

    controller.updateScalebyDelta(1, focalPoint: Offset.zero);
    controller.onScaleStart(ScaleStartDetails(focalPoint: Offset.zero));
    controller.onScaleEnd(
      ScaleEndDetails(
        velocity: const Velocity(pixelsPerSecond: Offset(1000, 0)),
      ),
    );
    await tester.pumpAndSettle();

    final screenDistance = FrictionSimulation(
      controller.inertiaFrictionCoefficient,
      0,
      1000,
    ).finalX;
    expect(controller.offset.dx, closeTo(-screenDistance / 2, 0.01));
    expect(controller.offset.dy, 0);
  });

  testWidgets('cancels inertia when a new gesture starts', (
    WidgetTester tester,
  ) async {
    final controller = LazyCanvasController();
    await _pumpCanvas(tester, controller);

    controller.onScaleStart(ScaleStartDetails(focalPoint: Offset.zero));
    controller.onScaleEnd(
      ScaleEndDetails(
        velocity: const Velocity(pixelsPerSecond: Offset(1000, 0)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    controller.onScaleStart(ScaleStartDetails(focalPoint: Offset.zero));
    final stoppedOffset = controller.offset;
    await tester.pump(const Duration(seconds: 1));

    expect(controller.offset, stoppedOffset);
  });

  testWidgets('skips inertia when disabled or after scaling', (
    WidgetTester tester,
  ) async {
    final disabledController = LazyCanvasController(inertiaEnabled: false);
    await _pumpCanvas(tester, disabledController);

    disabledController.onScaleStart(ScaleStartDetails(focalPoint: Offset.zero));
    disabledController.onScaleEnd(
      ScaleEndDetails(
        velocity: const Velocity(pixelsPerSecond: Offset(1000, 0)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(disabledController.offset, Offset.zero);

    final scaledController = LazyCanvasController();
    await _pumpCanvas(tester, scaledController);
    scaledController.onScaleStart(ScaleStartDetails(focalPoint: Offset.zero));
    scaledController.onScaleUpdate(
      ScaleUpdateDetails(focalPoint: Offset.zero, scale: 2),
    );
    scaledController.onScaleEnd(
      ScaleEndDetails(
        velocity: const Velocity(pixelsPerSecond: Offset(1000, 0)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(scaledController.offset, Offset.zero);
  });
}
