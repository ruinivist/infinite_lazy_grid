import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
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
  LazyCanvasController controller, {
  TouchNavigationMode touchNavigationMode = TouchNavigationMode.oneFinger,
  ValueChanged<bool>? onTouchNavigationChanged,
  int mousePanButtons = kPrimaryMouseButton,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: LazyCanvas(
        controller: controller,
        touchNavigationMode: touchNavigationMode,
        onTouchNavigationChanged: onTouchNavigationChanged,
        mousePanButtons: mousePanButtons,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _drag(
  WidgetTester tester, {
  required PointerDeviceKind kind,
  required int buttons,
}) async {
  final gesture = await tester.startGesture(
    const Offset(200, 200),
    kind: kind,
    buttons: buttons,
  );
  await gesture.moveBy(const Offset(40, 30));
  await gesture.up();
  await tester.pump();
}

void main() {
  testWidgets('two-finger ownership precedes raw delivery and transforms', (
    tester,
  ) async {
    final events = <String>[];
    final controller = LazyCanvasController(
      rawPointerDownListener: (_) => events.add('down'),
      rawPointerMoveListener: (_) => events.add('move'),
      rawPointerUpListener: (_) => events.add('up'),
    );
    controller.addListener(() => events.add('transform'));
    await tester.pumpWidget(
      MaterialApp(
        home: Padding(
          padding: const EdgeInsets.only(left: 60, top: 40),
          child: LazyCanvas(
            controller: controller,
            touchNavigationMode: TouchNavigationMode.twoFinger,
            onTouchNavigationChanged: (active) => events.add('owner:$active'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    events.clear();

    final first = await tester.startGesture(const Offset(100, 200), pointer: 1);
    await first.moveTo(const Offset(100, 220));
    expect(controller.offset, Offset.zero);
    expect(controller.scale, 1);
    expect(events, ['down', 'move']);

    final second = await tester.startGesture(
      const Offset(300, 220),
      pointer: 2,
    );
    expect(events, ['down', 'move', 'owner:true', 'down']);
    expect(controller.offset, Offset.zero);
    expect(controller.scale, 1);

    await first.moveTo(const Offset(50, 220));
    await second.moveTo(const Offset(350, 220));
    expect(controller.scale, closeTo(1.5, 1e-9));
    // The original canvas point beneath the centroid stays beneath it.
    final centroidCanvasPoint = const Offset(140, 180);
    final centroidScreenPoint =
        (centroidCanvasPoint - controller.offset) * controller.scale;
    expect(centroidScreenPoint.dx, closeTo(140, 1e-9));
    expect(centroidScreenPoint.dy, closeTo(180, 1e-9));

    await first.moveTo(const Offset(100, 220));
    await second.moveTo(const Offset(300, 220));
    expect(controller.scale, closeTo(1, 1e-9));
    expect(controller.offset.dx, closeTo(0, 1e-9));
    expect(controller.offset.dy, closeTo(0, 1e-9));
    await first.moveTo(const Offset(50, 220));
    await second.moveTo(const Offset(350, 220));

    final beforePan = controller.offset;
    await first.moveBy(const Offset(30, 40));
    await second.moveBy(const Offset(30, 40));
    expect(controller.scale, closeTo(1.5, 1e-9));
    expect(controller.offset.dx, closeTo(beforePan.dx - 20, 1e-9));
    expect(controller.offset.dy, closeTo(beforePan.dy - 40 / 1.5, 1e-9));
    expect(events.indexOf('owner:true'), lessThan(events.indexOf('transform')));

    await second.up();
    final frozenOffset = controller.offset;
    final frozenScale = controller.scale;
    await first.moveBy(const Offset(80, 20));
    expect(controller.offset, frozenOffset);
    expect(controller.scale, frozenScale);
    expect(events.where((event) => event.startsWith('owner')), ['owner:true']);
    await first.up();
    expect(events.where((event) => event.startsWith('owner')), [
      'owner:true',
      'owner:false',
    ]);
    await tester.pump(const Duration(seconds: 1));
    expect(controller.offset, frozenOffset);
  });

  testWidgets('rebases touch configuration and drains after cancellation', (
    tester,
  ) async {
    final ownership = <bool>[];
    final controller = LazyCanvasController();
    await _pumpCanvas(
      tester,
      controller,
      touchNavigationMode: TouchNavigationMode.twoFinger,
      onTouchNavigationChanged: ownership.add,
    );
    final first = await tester.startGesture(const Offset(100, 200), pointer: 1);
    final second = await tester.startGesture(
      const Offset(300, 200),
      pointer: 2,
    );
    await second.moveBy(const Offset(20, 40));
    final offset = controller.offset;
    final scale = controller.scale;
    final third = await tester.startGesture(const Offset(200, 300), pointer: 3);
    expect(controller.offset, offset);
    expect(controller.scale, scale);
    await third.cancel();
    expect(controller.offset, offset);
    expect(controller.scale, scale);
    await first.moveBy(const Offset(0, 30));
    expect(controller.offset, isNot(offset));

    await second.cancel();
    final frozen = controller.offset;
    final extra = await tester.startGesture(const Offset(400, 300), pointer: 4);
    await extra.moveBy(const Offset(50, 20));
    await first.moveBy(const Offset(30, 20));
    expect(controller.offset, frozen);
    expect(ownership, [true]);
    await first.cancel();
    expect(ownership, [true]);
    await extra.up();
    expect(ownership, [true, false]);

    final fresh = await tester.startGesture(const Offset(100, 200), pointer: 5);
    final partner = await tester.startGesture(
      const Offset(300, 200),
      pointer: 6,
    );
    await partner.moveBy(const Offset(40, 0));
    expect(controller.offset, isNot(frozen));
    await fresh.up();
    await partner.up();
    expect(ownership, [true, false, true, false]);
  });

  testWidgets('touch handoff cancels a tool after a child wins its drag', (
    tester,
  ) async {
    var navigating = false;
    var pendingTool = false;
    var commits = 0;
    var childMoves = 0;
    final controller = LazyCanvasController(
      rawPointerDownListener: (_) {
        if (!navigating) pendingTool = true;
      },
      rawPointerUpListener: (_) {
        if (pendingTool) commits++;
        pendingTool = false;
      },
    );
    controller.addChild(
      const Offset(100, 100),
      GestureDetector(
        onPanUpdate: (_) {
          if (!navigating) childMoves++;
        },
        child: Container(width: 160, height: 160, color: Colors.blue),
      ),
    );
    await _pumpCanvas(
      tester,
      controller,
      touchNavigationMode: TouchNavigationMode.twoFinger,
      onTouchNavigationChanged: (active) {
        navigating = active;
        if (active) pendingTool = false;
      },
    );
    final first = await tester.startGesture(const Offset(120, 120), pointer: 1);
    await first.moveBy(const Offset(50, 0));
    await first.moveBy(const Offset(20, 0));
    expect(childMoves, greaterThan(0));
    expect(pendingTool, isTrue);
    expect(controller.offset, Offset.zero);
    final previousMoves = childMoves;

    final second = await tester.startGesture(
      const Offset(400, 200),
      pointer: 2,
    );
    expect(navigating, isTrue);
    expect(pendingTool, isFalse);
    await first.moveBy(const Offset(30, 10));
    expect(controller.offset, isNot(Offset.zero));
    expect(childMoves, previousMoves);
    await first.up();
    await second.up();
    expect(commits, 0);
    expect(navigating, isFalse);
  });

  testWidgets('snapshots touch mode until release in both directions', (
    tester,
  ) async {
    final controller = LazyCanvasController(inertiaEnabled: false);
    final mode = ValueNotifier(TouchNavigationMode.twoFinger);
    addTearDown(mode.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder(
          valueListenable: mode,
          builder: (_, value, _) =>
              LazyCanvas(controller: controller, touchNavigationMode: value),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final first = await tester.startGesture(const Offset(100, 200), pointer: 1);
    mode.value = TouchNavigationMode.oneFinger;
    await tester.pump();
    await first.moveBy(const Offset(40, 20));
    expect(controller.offset, Offset.zero);
    final second = await tester.startGesture(
      const Offset(300, 200),
      pointer: 2,
    );
    await second.moveBy(const Offset(40, 20));
    expect(controller.offset, isNot(Offset.zero));
    await first.up();
    await second.up();

    final next = await tester.startGesture(const Offset(100, 200), pointer: 3);
    mode.value = TouchNavigationMode.twoFinger;
    await tester.pump();
    final before = controller.offset;
    await next.moveBy(const Offset(40, 20));
    expect(controller.offset, isNot(before));
    await next.up();
    final after = controller.offset;
    await _drag(tester, kind: PointerDeviceKind.touch, buttons: kPrimaryButton);
    expect(controller.offset, after);
  });

  testWidgets('two-finger mode retains other navigation and excludes stylus', (
    tester,
  ) async {
    final ownership = <bool>[];
    final controller = LazyCanvasController(inertiaEnabled: false);
    await _pumpCanvas(
      tester,
      controller,
      mousePanButtons: kSecondaryMouseButton | kMiddleMouseButton,
      touchNavigationMode: TouchNavigationMode.twoFinger,
      onTouchNavigationChanged: ownership.add,
    );
    final pen = await tester.startGesture(
      const Offset(100, 200),
      pointer: 1,
      kind: PointerDeviceKind.stylus,
    );
    final finger = await tester.startGesture(
      const Offset(300, 200),
      pointer: 2,
    );
    await pen.moveBy(const Offset(40, 20));
    await finger.moveBy(const Offset(40, 20));
    expect(controller.offset, Offset.zero);
    expect(controller.scale, 1);
    expect(ownership, isEmpty);
    final secondFinger = await tester.startGesture(
      const Offset(400, 200),
      pointer: 3,
    );
    await secondFinger.moveBy(const Offset(40, 20));
    expect(ownership, [true]);
    expect(controller.offset, isNot(Offset.zero));
    await pen.up();
    await finger.up();
    await secondFinger.up();

    final afterTouch = controller.offset;
    await _drag(tester, kind: PointerDeviceKind.mouse, buttons: kPrimaryButton);
    expect(controller.offset, afterTouch);
    for (final button in [kSecondaryMouseButton, kMiddleMouseButton]) {
      final before = controller.offset;
      await _drag(tester, kind: PointerDeviceKind.mouse, buttons: button);
      expect(controller.offset, isNot(before));
    }
    final trackpad = await tester.startGesture(
      const Offset(200, 200),
      kind: PointerDeviceKind.trackpad,
    );
    final beforeTrackpad = controller.offset;
    final beforeScale = controller.scale;
    await trackpad.panZoomUpdate(
      const Offset(200, 200),
      pan: const Offset(40, 30),
      scale: 1.5,
    );
    expect(controller.offset, isNot(beforeTrackpad));
    expect(controller.scale, closeTo(beforeScale * 1.5, 1e-9));
    await trackpad.panZoomEnd();
    final beforeWheel = controller.offset;
    await tester.sendEventToBinding(
      const PointerScrollEvent(
        position: Offset(200, 200),
        scrollDelta: Offset(0, 40),
      ),
    );
    expect(
      controller.offset.dy,
      closeTo(beforeWheel.dy + 40 / controller.scale, 1e-9),
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    final beforeWheelScale = controller.scale;
    await tester.sendEventToBinding(
      const PointerScrollEvent(
        position: Offset(200, 200),
        scrollDelta: Offset(0, -40),
      ),
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(controller.scale, closeTo(beforeWheelScale + 0.06, 1e-9));
    expect(ownership, [true, false]);
  });

  testWidgets(
    'first tool touch stops inertia and coincident touches stay finite',
    (tester) async {
      final controller = LazyCanvasController();
      await _pumpCanvas(
        tester,
        controller,
        touchNavigationMode: TouchNavigationMode.twoFinger,
      );
      controller.onScaleStart(ScaleStartDetails(focalPoint: Offset.zero));
      controller.onScaleEnd(
        ScaleEndDetails(
          velocity: const Velocity(pixelsPerSecond: Offset(1000, 0)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      final first = await tester.startGesture(
        const Offset(200, 200),
        pointer: 1,
      );
      final stopped = controller.offset;
      await tester.pump(const Duration(seconds: 1));
      expect(controller.offset, stopped);
      final second = await tester.startGesture(
        const Offset(200, 200),
        pointer: 2,
      );
      await second.moveBy(const Offset(40, 0));
      expect(controller.offset, stopped);
      await second.moveBy(const Offset(40, 0));
      expect(controller.scale.isFinite, isTrue);
      expect(controller.scale, greaterThan(0));
      await first.up();
      await second.up();
    },
  );

  testWidgets('configures mouse pan buttons without affecting touch', (
    tester,
  ) async {
    final controller = LazyCanvasController(inertiaEnabled: false);
    await tester.pumpWidget(
      MaterialApp(
        home: LazyCanvas(
          controller: controller,
          mousePanButtons: kSecondaryMouseButton | kMiddleMouseButton,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _drag(
      tester,
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryMouseButton,
    );
    expect(controller.offset, Offset.zero);

    await _drag(
      tester,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    expect(controller.offset.dx, lessThan(0));
    final afterSecondary = controller.offset;

    await _drag(
      tester,
      kind: PointerDeviceKind.mouse,
      buttons: kMiddleMouseButton,
    );
    expect(controller.offset.dx, lessThan(afterSecondary.dx));
    final afterMiddle = controller.offset;

    await _drag(tester, kind: PointerDeviceKind.touch, buttons: kPrimaryButton);
    expect(controller.offset.dx, lessThan(afterMiddle.dx));
    final afterTouch = controller.offset;

    final trackpad = await tester.startGesture(
      const Offset(200, 200),
      kind: PointerDeviceKind.trackpad,
    );
    await trackpad.panZoomUpdate(
      const Offset(240, 230),
      pan: const Offset(40, 30),
    );
    await trackpad.panZoomEnd();
    await tester.pump();
    expect(controller.offset.dx, lessThan(afterTouch.dx));
  });

  testWidgets('scrolls vertically and supports a replacement handler', (
    tester,
  ) async {
    final defaultController = LazyCanvasController();
    await _pumpCanvas(tester, defaultController);
    await tester.sendEventToBinding(
      const PointerScrollEvent(
        position: Offset(200, 200),
        scrollDelta: Offset(20, 40),
      ),
    );
    await tester.pump();
    expect(defaultController.offset, const Offset(0, 40));

    final controller = LazyCanvasController();
    Offset? receivedDelta;
    await tester.pumpWidget(
      MaterialApp(
        home: LazyCanvas(
          controller: controller,
          onPointerScroll: (controller, delta) {
            receivedDelta = delta;
            controller.scrollBy(delta * 2);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendEventToBinding(
      const PointerScrollEvent(
        position: Offset(200, 200),
        scrollDelta: Offset(20, 40),
      ),
    );
    await tester.pump();

    expect(receivedDelta, const Offset(0, 40));
    expect(controller.offset, const Offset(0, 80));
  });

  testWidgets('lets a nested scrollable consume wheel input', (tester) async {
    final canvasController = LazyCanvasController();
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    canvasController.addChild(
      Offset.zero,
      SizedBox(
        width: 100,
        height: 100,
        child: ListView(
          controller: scrollController,
          children: const [SizedBox(height: 500)],
        ),
      ),
    );
    await _pumpCanvas(tester, canvasController);

    await tester.sendEventToBinding(
      const PointerScrollEvent(
        position: Offset(20, 20),
        scrollDelta: Offset(0, 40),
      ),
    );
    await tester.pump();

    expect(scrollController.offset, greaterThan(0));
    expect(canvasController.offset, Offset.zero);
  });

  testWidgets('keeps control-wheel and pointer-scale zoom', (tester) async {
    final controller = LazyCanvasController();
    await _pumpCanvas(tester, controller);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendEventToBinding(
      const PointerScrollEvent(
        position: Offset(200, 200),
        scrollDelta: Offset(0, -40),
      ),
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(controller.scale, closeTo(1.06, 0.001));

    await tester.sendEventToBinding(
      const PointerScaleEvent(position: Offset(200, 200), scale: 1.4),
    );
    expect(controller.scale, closeTo(1.16, 0.001));
  });

  testWidgets('repaints when the background becomes ready', (tester) async {
    final background = TestBackground();
    final controller = LazyCanvasController(background: background);
    await _pumpCanvas(tester, controller);
    final initialPaintCount = background.paintCount;

    background.notify();
    await tester.pump();

    expect(background.paintCount, greaterThan(initialPaintCount));
  });

  testWidgets('repaints when the controller background changes', (
    tester,
  ) async {
    final initial = TestBackground();
    final replacement = TestBackground();
    final controller = LazyCanvasController(background: initial);
    await _pumpCanvas(tester, controller);

    controller.background = replacement;
    await tester.pump();

    expect(replacement.paintCount, greaterThan(0));
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
    expect(
      tester.getBottomRight(find.byKey(const ValueKey('test_child_0'))),
      const Offset(100, 100),
    );
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

  testWidgets('moves one child by a grid-space delta and returns its ID', (
    WidgetTester tester,
  ) async {
    final controller = LazyCanvasController();
    final id = controller.addChild(
      const Offset(10, 20),
      const TestChild(index: 0),
    );
    await _pumpCanvas(tester, controller);

    var notifications = 0;
    controller.addListener(() => notifications++);

    expect(controller.moveChildBy(id, const Offset(3, -4)), id);
    expect(notifications, 1);
    await tester.pump();

    expect(
      controller.widgetsWithScreenPositions().single.gsPosition,
      const Offset(13, 16),
    );
  });

  testWidgets('moves unique children once and updates lazy spatial lookup', (
    WidgetTester tester,
  ) async {
    final controller = LazyCanvasController(
      buildExtentMultiplier: 1,
      hashCellSize: const Size(10, 10),
    );
    final firstId = controller.addChild(
      const Offset(-100, 0),
      const TestChild(index: 0),
    );
    final secondId = controller.addChild(
      Offset.zero,
      const TestChild(index: 1),
    );
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

    var notifications = 0;
    controller.addListener(() => notifications++);
    controller.moveChildrenBy([
      firstId,
      firstId,
      secondId,
    ], const Offset(100, 0));
    expect(notifications, 1);
    await tester.pump();

    expect(
      controller.widgetsWithScreenPositions().map((child) => child.gsPosition),
      [Offset.zero, const Offset(100, 0)],
    );
  });

  testWidgets('validates every child before moving any child', (
    WidgetTester tester,
  ) async {
    final controller = LazyCanvasController();
    final id = controller.addChild(Offset.zero, const TestChild(index: 0));
    await _pumpCanvas(tester, controller);

    var notifications = 0;
    controller.addListener(() => notifications++);

    expect(
      () => controller.moveChildrenBy([id, 'missing'], const Offset(10, 10)),
      throwsA(isA<Exception>()),
    );
    expect(notifications, 0);
    expect(
      controller
          .widgetsWithScreenPositions(forceRebuild: true)
          .single
          .gsPosition,
      Offset.zero,
    );
  });

  testWidgets('does nothing when moving an empty child list', (
    WidgetTester tester,
  ) async {
    final controller = LazyCanvasController();
    final id = controller.addChild(Offset.zero, const TestChild(index: 0));
    await _pumpCanvas(tester, controller);

    var notifications = 0;
    controller.addListener(() => notifications++);
    controller.moveChildrenBy(const [], const Offset(10, 10));

    expect(notifications, 0);
    expect(controller.widgetsWithScreenPositions().single.id, id);
    expect(
      controller.widgetsWithScreenPositions().single.gsPosition,
      Offset.zero,
    );
  });

  testWidgets('moveChildrenBy mounts and unmounts children lazily', (
    WidgetTester tester,
  ) async {
    final controller = LazyCanvasController(
      buildExtentMultiplier: 1,
      hashCellSize: const Size(10, 10),
    );
    final id = controller.addChild(
      const Offset(500, 0),
      const TestChild(index: 0),
    );
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
    expect(find.byType(TestChild), findsNothing);

    controller.moveChildrenBy([id], const Offset(-500, 0));
    await tester.pump();
    expect(find.byType(TestChild), findsOneWidget);

    controller.moveChildrenBy([id], const Offset(500, 0));
    await tester.pump();
    expect(find.byType(TestChild), findsNothing);
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
      buildExtentMultiplier: 1,
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

  testWidgets('builds twice the viewport by default', (
    WidgetTester tester,
  ) async {
    final controller = LazyCanvasController(hashCellSize: const Size(10, 10));
    controller.addChild(const Offset(250, 0), const TestChild(index: 0));
    controller.addChild(const Offset(350, 0), const TestChild(index: 1));

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

    expect(find.byKey(const ValueKey('test_child_0')), findsOneWidget);
    expect(find.byKey(const ValueKey('test_child_1')), findsNothing);
  });

  testWidgets('updates the build region after viewport resize', (
    WidgetTester tester,
  ) async {
    final controller = LazyCanvasController(hashCellSize: const Size(10, 10));
    controller.addChild(const Offset(500, 0), const TestChild(index: 0));

    Widget canvas(double width) => MaterialApp(
      home: Center(
        child: SizedBox(
          width: width,
          height: 200,
          child: LazyCanvas(controller: controller),
        ),
      ),
    );

    await tester.pumpWidget(canvas(200));
    await tester.pumpAndSettle();
    expect(find.byType(TestChild), findsNothing);

    await tester.pumpWidget(canvas(400));
    await tester.pumpAndSettle();
    expect(find.byType(TestChild), findsOneWidget);

    await tester.pumpWidget(canvas(200));
    await tester.pumpAndSettle();
    expect(find.byType(TestChild), findsNothing);
  });

  testWidgets('keeps the build region relative while zooming', (
    WidgetTester tester,
  ) async {
    final controller = LazyCanvasController(hashCellSize: const Size(10, 10));
    controller.addChild(const Offset(250, 0), const TestChild(index: 0));

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
    expect(find.byType(TestChild), findsOneWidget);

    controller.updateScalebyDelta(1, focalPoint: const Offset(100, 100));
    await tester.pumpAndSettle();

    expect(find.byType(TestChild), findsNothing);
  });

  testWidgets('keeps a partially visible scaled child mounted', (
    WidgetTester tester,
  ) async {
    final controller = LazyCanvasController(hashCellSize: const Size(10, 10));
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
