// Verifies read-only rectangle queries against measured, rotated child layouts.
// Exercises the public controller before layout and after lazy culling.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_lazy_grid/infinite_lazy_grid.dart';

// ---------- Fixtures ----------

void addChild(
  LazyCanvasController controller,
  String id, {
  Offset position = Offset.zero,
  Size? size = const Size(100, 100),
  double rotation = 0,
}) {
  controller.addChild(
    position,
    SizedBox.fromSize(size: size),
    id: id,
    childSize: size,
    rotation: rotation,
  );
}

// ---------- Overlap queries ----------

void main() {
  test('uses precise rotated footprints rather than bounding boxes', () {
    final controller = LazyCanvasController();
    addTearDown(controller.dispose);
    addChild(
      controller,
      'rotated',
      size: const Size(100, 10),
      rotation: pi / 4,
    );

    expect(
      controller.overlappingChildren(const Rect.fromLTWH(12, 30, 5, 5)),
      isEmpty,
    );
    expect(controller.overlappingChildren(const Rect.fromLTWH(76, 29, 5, 5)), [
      'rotated',
    ]);
  });

  test('skips unknown and empty sizes and requires positive overlap', () {
    final controller = LazyCanvasController();
    addTearDown(controller.dispose);
    addChild(controller, 'known');
    addChild(controller, 'unknown', size: null);
    addChild(controller, 'empty', size: Size.zero);

    expect(controller.overlappingChildren(const Rect.fromLTWH(99, 0, 10, 10)), [
      'known',
    ]);
    expect(
      controller.overlappingChildren(const Rect.fromLTWH(100, 0, 10, 10)),
      isEmpty,
    );
    expect(controller.overlappingChildren(Rect.zero), isEmpty);
    expect(
      controller.overlappingChildren(const Rect.fromLTRB(10, 10, 0, 0)),
      isEmpty,
    );
    controller.onChildSizeChange('unknown', const Size(20, 20));
    expect(controller.overlappingChildren(const Rect.fromLTWH(0, 0, 10, 10)), [
      'known',
      'unknown',
    ]);
  });

  test('returns stable stack snapshots without mutating or notifying', () {
    final controller = LazyCanvasController();
    addTearDown(controller.dispose);
    addChild(controller, 'a');
    addChild(controller, 'b');
    controller.setChildOrder(['b', 'a']);
    var notifications = 0;
    controller.addListener(() => notifications++);

    final result = controller.overlappingChildren(
      const Rect.fromLTWH(0, 0, 10, 10),
    );
    expect(result, ['b', 'a']);
    expect(() => result.clear(), throwsUnsupportedError);
    expect(controller.childOrder, ['b', 'a']);
    expect(controller.getInfo('a').gsPosition, Offset.zero);
    expect(controller.getInfo('a').childSize, const Size(100, 100));
    expect(notifications, 0);

    for (final value in [
      double.nan,
      double.infinity,
      double.negativeInfinity,
    ]) {
      expect(
        () => controller.overlappingChildren(Rect.fromLTRB(value, 0, 10, 10)),
        throwsArgumentError,
      );
      expect(notifications, 0);
      expect(controller.childOrder, ['b', 'a']);
    }
    controller.update('a', position: const Offset(200, 200));
    expect(result, ['b', 'a']);
    expect(controller.overlappingChildren(const Rect.fromLTWH(0, 0, 10, 10)), [
      'b',
    ]);
  });

  testWidgets('retains measured footprints after culling, pan and zoom', (
    tester,
  ) async {
    final controller = LazyCanvasController();
    addTearDown(controller.dispose);
    controller.addChild(
      const Offset(20, 20),
      const SizedBox(key: ValueKey('measured'), width: 80, height: 40),
      id: 'measured',
      rotation: pi / 2,
    );
    await tester.pumpWidget(
      MaterialApp(home: LazyCanvas(controller: controller)),
    );
    await tester.pumpAndSettle();
    const query = Rect.fromLTWH(55, 1, 10, 10);
    expect(controller.getInfo('measured').childSize, const Size(80, 40));
    expect(controller.overlappingChildren(query), ['measured']);

    controller
      ..updateScalebyDelta(0.5, focalPoint: Offset.zero)
      ..onScaleStart(ScaleStartDetails())
      ..onScaleUpdate(
        ScaleUpdateDetails(focalPointDelta: const Offset(-5000, -5000)),
      );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('measured')), findsNothing);
    expect(controller.getInfo('measured').childSize, const Size(80, 40));
    expect(controller.overlappingChildren(query), ['measured']);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
