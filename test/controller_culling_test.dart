import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_lazy_grid/infinite_lazy_grid.dart';

Future<void> pumpCanvas(
  WidgetTester tester,
  LazyCanvasController controller, {
  Size size = const Size(200, 200),
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox.fromSize(
          size: size,
          child: LazyCanvas(controller: controller),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('horizontal padding validates and scales the complete build extent', () {
    for (final padding in [
      double.nan,
      double.infinity,
      double.negativeInfinity,
      -1.0,
    ]) {
      expect(
        () => LazyCanvasController(minHorizontalBuildPadding: padding),
        throwsArgumentError,
      );
    }

    final controller = LazyCanvasController(buildExtentMultiplier: 1);
    addTearDown(controller.dispose);
    expect(controller.minHorizontalBuildPadding, 200);
    controller.onCanvasSizeChange(const Size(360, 720));
    expect(controller.buildExtent, const Offset(760, 720));
    controller.updateScalebyDelta(-0.5, focalPoint: const Offset(180, 360));
    expect(controller.buildExtent, const Offset(1520, 1440));
    controller.updateScalebyDelta(1.5, focalPoint: const Offset(180, 360));
    expect(controller.buildExtent, const Offset(380, 360));

    final noPadding = LazyCanvasController(
      buildExtentMultiplier: 1,
      minHorizontalBuildPadding: -0.0,
    );
    addTearDown(noPadding.dispose);
    noPadding.onCanvasSizeChange(const Size(360, 720));
    expect(noPadding.buildExtent, const Offset(360, 720));
  });

  test(
    'measurement updates coalesce and ignore pending work after dispose',
    () async {
      final controller = LazyCanvasController();
      final id = controller.addChild(Offset.zero, const SizedBox());
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.onChildSizeChange(id, const Size(20, 20));
      controller.onChildSizeChange(id, const Size(40, 40));
      controller.onChildSizeChange(id, const Size(40, 40));
      expect(notifications, 0);
      await Future<void>.delayed(Duration.zero);
      expect(notifications, 1);
      expect(controller.getInfo(id).childSize, const Size(40, 40));

      controller.onChildSizeChange(id, const Size(60, 60));
      controller.dispose();
      await Future<void>.delayed(Duration.zero);
    },
  );

  testWidgets('known wide bounds overlap before their origin enters', (
    tester,
  ) async {
    final controller = LazyCanvasController(
      buildExtentMultiplier: 1,
      minHorizontalBuildPadding: 0,
    );
    addTearDown(controller.dispose);
    final id = controller.addChild(
      const Offset(-220, 20),
      const SizedBox(key: ValueKey('wide'), width: 300, height: 40),
      childSize: const Size(300, 40),
    );
    await pumpCanvas(tester, controller, size: const Size(400, 200));
    expect(find.byKey(const ValueKey('wide')), findsOneWidget);
    expect(controller.widgetsWithScreenPositions().single.id, id);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('unknown wide children are discovered by origin, then bounds', (
    tester,
  ) async {
    final controller = LazyCanvasController(
      buildExtentMultiplier: 1,
      minHorizontalBuildPadding: 0,
    );
    addTearDown(controller.dispose);
    final id = controller.addChild(
      const Offset(-220, 20),
      const SizedBox(key: ValueKey('unknown-wide'), width: 300, height: 40),
    );
    await pumpCanvas(tester, controller, size: const Size(400, 200));
    expect(find.byKey(const ValueKey('unknown-wide')), findsNothing);
    expect(controller.getInfo(id).childSize, isNull);

    controller.scrollBy(const Offset(-420, 0));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('unknown-wide')), findsOneWidget);
    expect(controller.getInfo(id).childSize, const Size(300, 40));

    controller.scrollBy(const Offset(420, 0));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('unknown-wide')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('focus size indexes a culled child before normal layout', (
    tester,
  ) async {
    final controller = LazyCanvasController(
      buildExtentMultiplier: 1,
      minHorizontalBuildPadding: 0,
    );
    addTearDown(controller.dispose);
    final id = controller.addChild(
      const Offset(-220, 20),
      const SizedBox(key: ValueKey('focused-wide'), width: 300, height: 40),
    );
    await pumpCanvas(tester, controller, size: const Size(400, 200));
    expect(find.byKey(const ValueKey('focused-wide')), findsNothing);

    controller.focusOnChild(id, childSize: const Size(300, 40), animate: false);
    expect(controller.getInfo(id).childSize, const Size(300, 40));
    controller.scrollBy(const Offset(270, 60));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('focused-wide')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('measured constrained size refreshes bounds without churn', (
    tester,
  ) async {
    final entered = <String>[];
    final exited = <String>[];
    final controller = LazyCanvasController(
      buildExtentMultiplier: 1,
      minHorizontalBuildPadding: 0,
      onWidgetEnteredRender: entered.add,
      onWidgetExitedRender: exited.add,
    );
    addTearDown(controller.dispose);
    controller.addChild(
      const Offset(-220, 20),
      const SizedBox(key: ValueKey('constrained'), width: 300, height: 40),
      id: 'constrained',
      childSize: const Size(300, 40),
    );

    await pumpCanvas(tester, controller);
    expect(controller.getInfo('constrained').childSize, const Size(200, 40));
    expect(find.byKey(const ValueKey('constrained')), findsNothing);
    expect(entered, ['constrained']);
    expect(exited, ['constrained']);

    await tester.pump();
    await tester.pump();
    expect(entered, ['constrained']);
    expect(exited, ['constrained']);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'offscreen geometry, rotation, replacement, remove and clear update lookup',
    (tester) async {
      final callbacks = <String>[];
      final controller = LazyCanvasController(
        buildExtentMultiplier: 1,
        minHorizontalBuildPadding: 0,
        onWidgetEnteredRender: (id) => callbacks.add('+$id'),
        onWidgetExitedRender: (id) => callbacks.add('-$id'),
      );
      addTearDown(controller.dispose);
      const key = ValueKey('reused-child');
      controller.addChild(
        const Offset(500, 20),
        const SizedBox(key: key, width: 20, height: 20),
        childSize: const Size(20, 20),
        id: 'reused',
      );
      controller.addChild(
        const Offset(0, 20),
        const SizedBox(key: ValueKey('peer-child'), width: 20, height: 20),
        childSize: const Size(20, 20),
        id: 'peer',
      );
      await pumpCanvas(tester, controller);
      expect(find.byKey(key), findsNothing);
      expect(find.byKey(const ValueKey('peer-child')), findsOneWidget);

      controller.update('reused', childSize: const Size(600, 20));
      await tester.pumpAndSettle();
      expect(find.byKey(key), findsNothing);
      controller.update('reused', position: const Offset(-19, 20));
      await tester.pumpAndSettle();
      expect(find.byKey(key), findsOneWidget);

      controller.update('reused', position: const Offset(500, 20));
      await tester.pumpAndSettle();
      expect(find.byKey(key), findsNothing);
      controller.update(
        'reused',
        position: const Offset(220, 20),
        childSize: const Size(20, 100),
        widget: const SizedBox(key: key, width: 20, height: 100),
        rotation: pi / 2,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(key), findsOneWidget);

      controller.addChild(
        const Offset(500, 20),
        const SizedBox(key: key, width: 20, height: 20),
        childSize: const Size(20, 20),
        id: 'reused',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(key), findsNothing);
      expect(find.byKey(const ValueKey('peer-child')), findsOneWidget);
      controller.update('reused', position: const Offset(-19, 20));
      await tester.pumpAndSettle();
      expect(find.byKey(key), findsOneWidget);

      controller.removeChild('reused');
      await tester.pumpAndSettle();
      expect(find.byKey(key), findsNothing);
      expect(find.byKey(const ValueKey('peer-child')), findsOneWidget);
      controller.addChild(
        const Offset(500, 20),
        const SizedBox(key: key, width: 20, height: 20),
        childSize: const Size(20, 20),
        id: 'reused',
      );
      controller.update('reused', position: const Offset(-19, 20));
      await tester.pumpAndSettle();
      expect(find.byKey(key), findsOneWidget);
      expect(callbacks.where((event) => event == '+reused').length, 4);

      controller.clear();
      await tester.pumpAndSettle();
      expect(find.byKey(key), findsNothing);
      controller.addChild(
        const Offset(-19, 20),
        const SizedBox(key: key, width: 20, height: 20),
        childSize: const Size(20, 20),
        id: 'reused',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(key), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('screen-space minimum follows portrait, landscape and zoom', (
    tester,
  ) async {
    final entered = <String>[];
    final exited = <String>[];
    final controller = LazyCanvasController(
      buildExtentMultiplier: 1,
      onWidgetEnteredRender: (id) => entered.add(id),
      onWidgetExitedRender: (id) => exited.add(id),
    );
    addTearDown(controller.dispose);
    controller.addChild(
      const Offset(600, 20),
      const SizedBox(key: ValueKey('orientation-child'), width: 1, height: 1),
      id: 'orientation',
    );

    await pumpCanvas(tester, controller, size: const Size(360, 720));
    expect(find.byKey(const ValueKey('orientation-child')), findsNothing);
    await pumpCanvas(tester, controller, size: const Size(720, 360));
    expect(find.byKey(const ValueKey('orientation-child')), findsOneWidget);
    await pumpCanvas(tester, controller, size: const Size(360, 720));
    expect(find.byKey(const ValueKey('orientation-child')), findsNothing);

    controller.updateScalebyDelta(-0.5, focalPoint: const Offset(180, 360));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('orientation-child')), findsOneWidget);
    controller.updateScalebyDelta(1.5, focalPoint: const Offset(180, 360));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('orientation-child')), findsNothing);
    expect(entered, ['orientation', 'orientation']);
    expect(exited, ['orientation', 'orientation']);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('empty sizes use their origin and edge contact is retained', (
    tester,
  ) async {
    final controller = LazyCanvasController(
      buildExtentMultiplier: 1,
      minHorizontalBuildPadding: 0,
    );
    addTearDown(controller.dispose);
    controller.addChild(
      const Offset(200, 20),
      const SizedBox(key: ValueKey('edge-child')),
      childSize: Size.zero,
    );
    controller.addChild(
      const Offset(-100, 40),
      const SizedBox(key: ValueKey('negative-child'), width: 100, height: 10),
      childSize: const Size(100, 10),
    );
    await pumpCanvas(tester, controller);
    expect(find.byKey(const ValueKey('edge-child')), findsOneWidget);
    expect(find.byKey(const ValueKey('negative-child')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
