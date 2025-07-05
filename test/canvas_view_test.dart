import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:infinite_lazy_2d_grid/core/render.dart';
import 'package:infinite_lazy_2d_grid/core/controller/controller.dart';
import 'package:infinite_lazy_2d_grid/core/background.dart';

class TestChild extends StatelessWidget {
  final int index;
  const TestChild({required this.index, super.key});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(child: SizedBox(key: ValueKey('test_child_$index'), width: 50, height: 50));
  }
}

void main() {
  testWidgets('CanvasView renders only visible children and reduces count on zoom out', (WidgetTester tester) async {
    final controller = CanvasController(debug: true, initialScale: 1);
    for (int i = 0; i < 10000; i++) {
      controller.addChild(Offset((i % 80) * 100.0, (i ~/ 80) * 100.0), () => TestChild(index: i));
    }
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CanvasView(controller: controller, canvasBackground: SingleColorBackround(Colors.white)),
        ),
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
  });

  testWidgets('CanvasView scales as expected', (WidgetTester tester) async {
    final controller = CanvasController(debug: true, initialScale: 1);
    controller.addChild(const Offset(0, 0), () => TestChild(index: 0));
    controller.addChild(const Offset(100, 100), () => TestChild(index: 1));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CanvasView(controller: controller, canvasBackground: SingleColorBackround(Colors.white)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Initial size check
    final finder = find.byType(TestChild);
    expect(finder, findsNWidgets(2));

    // Simulate a scale update to 2x, keeping the top-left at (0,0)
    controller.onScaleStart(ScaleStartDetails(focalPoint: const Offset(0, 0)));
    controller.onScaleUpdate(ScaleUpdateDetails(focalPoint: const Offset(0, 0), scale: 2.0));
    await tester.pumpAndSettle();
    expect(controller.scale, 2.0);
    final ssPositions = controller.widgetsWithScreenPositions().map((e) => e.ssPosition).toList();
    expect(ssPositions, [Offset.zero, const Offset(200, 200)]);
  });
}
