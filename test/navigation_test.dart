import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_lazy_grid/infinite_lazy_grid.dart';

import 'touch_test_helpers.dart';

Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets(
    'identity wrapper disables every default input path and observes raw events once',
    (tester) async {
      final events = <String>[];
      final controller = LazyCanvasController(
        rawPointerDownListener: (_) => events.add('down'),
        rawPointerMoveListener: (_) => events.add('move'),
        rawPointerUpListener: (_) => events.add('up'),
        rawPointerSignalListener: (_) => events.add('signal'),
      );
      var wheelCalls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: LazyCanvas(
            controller: controller,
            navigationBuilder: (_, child) => child,
            onPointerScroll: (_, _) => wheelCalls++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final kind in [PointerDeviceKind.touch, PointerDeviceKind.mouse]) {
        final gesture = await tester.startGesture(
          const Offset(200, 200),
          kind: kind,
        );
        await gesture.moveBy(const Offset(100, 60));
        await gesture.up();
      }
      final trackpad = await tester.startGesture(
        const Offset(200, 200),
        kind: PointerDeviceKind.trackpad,
      );
      await trackpad.panZoomUpdate(
        const Offset(300, 260),
        pan: const Offset(100, 60),
        scale: 2,
      );
      await trackpad.panZoomEnd();
      await tester.sendEventToBinding(
        const PointerScrollEvent(
          position: Offset(200, 200),
          scrollDelta: Offset(30, 40),
        ),
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendEventToBinding(
        const PointerScrollEvent(
          position: Offset(200, 200),
          scrollDelta: Offset(0, -40),
        ),
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendEventToBinding(
        const PointerScaleEvent(position: Offset(200, 200), scale: 2),
      );
      await tester.pumpAndSettle();
      expect(controller.offset, Offset.zero);
      expect(controller.scale, 1);
      expect(wheelCalls, 0);
      expect(events, [
        'down',
        'move',
        'up',
        'down',
        'move',
        'up',
        'signal',
        'signal',
        'signal',
      ]);
    },
  );

  testWidgets(
    'custom wrapper controls transforms and signals without default handlers',
    (tester) async {
      final controller = LazyCanvasController(
        inertiaEnabled: false,
        maxScale: 1.5,
      );
      var wheelCalls = 0;
      var customSignals = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Padding(
            padding: const EdgeInsets.only(left: 60, top: 40),
            child: LazyCanvas(
              controller: controller,
              mousePanButtons: 0,
              onPointerScroll: (_, _) => wheelCalls++,
              navigationBuilder: (_, child) => Listener(
                behavior: HitTestBehavior.translucent,
                onPointerSignal: (event) {
                  GestureBinding.instance.pointerSignalResolver.register(
                    event,
                    (_) {
                      customSignals++;
                      controller.updateScalebyDelta(
                        10,
                        focalPoint: Offset.zero,
                      );
                    },
                  );
                },
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onScaleStart: controller.onScaleStart,
                  onScaleUpdate: controller.onScaleUpdate,
                  onScaleEnd: controller.onScaleEnd,
                  child: child,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(
        const Offset(200, 200),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(80, 40));
      await gesture.moveBy(const Offset(20, 10));
      await gesture.up();
      await tester.pump();
      expect(controller.offset, isNot(Offset.zero));
      final before = controller.offset;
      await tester.sendEventToBinding(
        const PointerScrollEvent(
          position: Offset(200, 200),
          scrollDelta: Offset(30, 40),
        ),
      );
      await tester.pump();
      expect(controller.scale, 1.5);
      expect(controller.offset, before);
      expect(customSignals, 1);
      expect(wheelCalls, 0);
    },
  );

  testWidgets(
    'default navigation includes composed overlays in its gesture region',
    (tester) async {
      final controller = LazyCanvasController(inertiaEnabled: false);
      await tester.pumpWidget(
        MaterialApp(
          home: LazyCanvas(
            controller: controller,
            viewportBuilder: (_, viewport) => Stack(
              children: [
                viewport,
                const Positioned(
                  left: 20,
                  top: 20,
                  width: 120,
                  height: 120,
                  child: ColoredBox(color: Colors.red),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final first = await tester.startGesture(const Offset(50, 50), pointer: 1);
      await first.moveBy(const Offset(60, 40));
      await _frames(tester);
      expect(controller.offset, const Offset(-60, -40));
      final second = await tester.startGesture(
        const Offset(350, 200),
        pointer: 2,
      );
      final before = touchView(controller);
      await first.moveBy(const Offset(20, 10));
      await second.moveBy(const Offset(20, 10));
      await _frames(tester);
      expectTouchView(touchView(controller), (
        offset: before.offset - const Offset(20, 10),
        scale: 1,
      ), 'overlay and viewport contacts share navigation');
      await first.up();
      await second.up();
    },
  );

  testWidgets('custom wrapper receives composed overlay input', (tester) async {
    final controller = LazyCanvasController();
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: LazyCanvas(
          controller: controller,
          viewportBuilder: (_, viewport) => Stack(
            children: [
              viewport,
              const Positioned(
                left: 20,
                top: 20,
                width: 100,
                height: 100,
                child: ColoredBox(color: Colors.red),
              ),
            ],
          ),
          navigationBuilder: (_, child) =>
              GestureDetector(onTap: () => taps++, child: child),
        ),
      ),
    );
    await tester.tapAt(const Offset(40, 40));
    expect(taps, 1);
  });

  testWidgets('navigation does not take over a winning child drag', (
    tester,
  ) async {
    final controller = LazyCanvasController(inertiaEnabled: false);
    var moves = 0;
    controller.addChild(
      const Offset(20, 20),
      GestureDetector(
        onPanUpdate: (_) => moves++,
        child: const ColoredBox(
          color: Colors.red,
          child: SizedBox(width: 200, height: 200),
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: LazyCanvas(controller: controller)),
    );
    await tester.pumpAndSettle();
    final first = await tester.startGesture(const Offset(50, 50), pointer: 1);
    await first.moveBy(const Offset(60, 20));
    await first.moveBy(const Offset(20, 10));
    expect(moves, greaterThan(0));
    final before = moves;
    final second = await tester.startGesture(
      const Offset(400, 300),
      pointer: 2,
    );
    await first.moveBy(const Offset(20, 10));
    await second.up();
    await first.up();
    await _frames(tester);
    expect(moves, greaterThan(before));
    expect(controller.offset, Offset.zero);
    expect(controller.scale, 1);
  });

  testWidgets(
    'touch slop preserves taps and qualifying pan includes full displacement',
    (tester) async {
      final controller = LazyCanvasController(inertiaEnabled: false);
      await tester.pumpWidget(
        MaterialApp(home: LazyCanvas(controller: controller)),
      );
      await tester.pumpAndSettle();
      final tap = await tester.startGesture(const Offset(200, 200));
      await tap.moveBy(const Offset(1, 1));
      await tap.up();
      await _frames(tester);
      expect(controller.offset, Offset.zero);
      final drag = await tester.startGesture(const Offset(200, 200));
      await drag.moveBy(const Offset(100, 60));
      await _frames(tester);
      expect(controller.offset, const Offset(-100, -60));
      await drag.up();
    },
  );

  for (final canceled in [false, true]) {
    testWidgets(
      'contacts transition without jumps after ${canceled ? 'cancellation' : 'release'}',
      (tester) async {
        await pumpTouchCanvas(tester);
        final controller = tester
            .widget<LazyCanvas>(find.byType(LazyCanvas))
            .controller;
        final first = await startTouchNavigation(
          tester,
          const Offset(250, 340),
          pointer: 1,
        );
        await first.moveBy(const Offset(20, 10));
        await _frames(tester);
        var expected = touchView(controller);
        final second = await tester.startGesture(
          const Offset(490, 340),
          pointer: 2,
        );
        expectTouchView(
          touchView(controller),
          expected,
          'adding a contact does not move the viewport',
        );
        const delta = Offset(30, 10);
        await first.moveBy(delta);
        await second.moveBy(delta);
        expected = (offset: expected.offset - delta, scale: expected.scale);
        await pumpTouchResponse(
          tester,
          previous: touchView(controller),
          target: expected,
        );
        if (canceled) {
          await second.cancel();
        } else {
          await second.up();
        }
        expectTouchView(
          touchView(controller),
          expected,
          'removing a contact does not jump',
        );
        await first.moveBy(delta);
        expected = (offset: expected.offset - delta, scale: expected.scale);
        await _frames(tester);
        expectTouchView(
          touchView(controller),
          expected,
          'the survivor continues panning',
        );
        final replacement = await tester.startGesture(
          const Offset(500, 350),
          pointer: 3,
        );
        expectTouchView(
          touchView(controller),
          expected,
          'a replacement joins without a jump',
        );
        await first.moveBy(delta);
        await replacement.moveBy(delta);
        expected = (offset: expected.offset - delta, scale: expected.scale);
        await _frames(tester);
        expectTouchView(
          touchView(controller),
          expected,
          'the replacement participates',
        );
        await first.up();
        await replacement.up();
        await pumpTouchHold(tester, expected: expected);
      },
    );
  }

  testWidgets('additional contacts participate and rebase without jumps', (
    tester,
  ) async {
    await pumpTouchCanvas(tester);
    final controller = tester
        .widget<LazyCanvas>(find.byType(LazyCanvas))
        .controller;
    final first = await startTouchNavigation(
      tester,
      const Offset(200, 250),
      pointer: 1,
    );
    final second = await tester.startGesture(
      const Offset(400, 250),
      pointer: 2,
    );
    final third = await tester.startGesture(const Offset(300, 450), pointer: 3);
    expectTouchView(touchView(controller), (
      offset: Offset.zero,
      scale: 1,
    ), 'third contact rebases');
    const delta = Offset(20, 10);
    for (final finger in [first, second, third]) {
      await finger.moveBy(delta);
    }
    await _frames(tester);
    expectTouchView(touchView(controller), (
      offset: -delta,
      scale: 1,
    ), 'all contacts pan together');
    await third.moveBy(const Offset(0, 60));
    await _frames(tester);
    final expanded = touchView(controller);
    expect(
      expanded.scale,
      greaterThan(1),
      reason: 'the third contact contributes to pinch geometry',
    );
    await third.up();
    expectTouchView(
      touchView(controller),
      expanded,
      'lifting third contact rebases',
    );
    await first.moveBy(delta);
    await second.moveBy(delta);
    await _frames(tester);
    expectTouchView(touchView(controller), (
      offset: expanded.offset - delta / expanded.scale,
      scale: expanded.scale,
    ), 'remaining contacts continue');
    await first.up();
    await second.up();
  });

  for (final canceled in [false, true]) {
    testWidgets(
      'two-contact translation ${canceled ? 'cancels without inertia' : 'can finish with inertia'}',
      (tester) async {
        final controller = LazyCanvasController(
          background: const NoBackground(),
        );
        await pumpTouchCanvas(tester, controller: controller);
        final first = await startTouchNavigation(
          tester,
          const Offset(200, 250),
          pointer: 1,
        );
        final second = await tester.startGesture(
          const Offset(400, 250),
          pointer: 2,
        );
        for (var i = 1; i <= 4; i++) {
          final time = Duration(milliseconds: i * 16);
          await first.moveBy(const Offset(40, 0), timeStamp: time);
          await second.moveBy(const Offset(40, 0), timeStamp: time);
          await tester.pump(const Duration(milliseconds: 16));
        }
        if (canceled) {
          await first.cancel(timeStamp: const Duration(milliseconds: 65));
        } else {
          await first.up(timeStamp: const Duration(milliseconds: 65));
        }
        await second.up(timeStamp: const Duration(milliseconds: 65));
        final before = controller.offset;
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
        if (canceled) {
          expect(controller.offset, before);
        } else {
          expect(controller.offset.dx, lessThan(before.dx));
        }
        controller.stopAnimation();
      },
    );
  }

  testWidgets('pinching suppresses inertia after returning to one contact', (
    tester,
  ) async {
    final controller = LazyCanvasController(background: const NoBackground());
    await pumpTouchCanvas(tester, controller: controller);
    final first = await startTouchNavigation(
      tester,
      const Offset(200, 250),
      pointer: 1,
    );
    final second = await tester.startGesture(
      const Offset(400, 250),
      pointer: 2,
    );
    await first.moveBy(
      const Offset(-40, 0),
      timeStamp: const Duration(milliseconds: 16),
    );
    await second.moveBy(
      const Offset(40, 0),
      timeStamp: const Duration(milliseconds: 16),
    );
    await tester.pump(const Duration(milliseconds: 16));
    expect(controller.scale, greaterThan(1));
    await second.up(timeStamp: const Duration(milliseconds: 17));
    for (var i = 2; i <= 5; i++) {
      await first.moveBy(
        const Offset(40, 0),
        timeStamp: Duration(milliseconds: i * 16),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    await first.up(timeStamp: const Duration(milliseconds: 81));
    final before = touchView(controller);
    await pumpTouchHold(tester, expected: before);
  });

  testWidgets(
    'replacing the navigation wrapper cancels queued work and held input',
    (tester) async {
      final controller = LazyCanvasController(inertiaEnabled: false);
      final disabled = ValueNotifier(false);
      addTearDown(disabled.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder(
            valueListenable: disabled,
            builder: (_, value, _) => LazyCanvas(
              controller: controller,
              navigationBuilder: value ? (_, child) => child : null,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final first = await startTouchNavigation(
        tester,
        const Offset(200, 250),
        pointer: 1,
      );
      final second = await tester.startGesture(
        const Offset(400, 250),
        pointer: 2,
      );
      await second.moveBy(const Offset(20, 10));
      disabled.value = true;
      await tester.pump();
      await first.moveBy(const Offset(40, 20));
      await second.moveBy(const Offset(40, 20));
      await _frames(tester);
      expectTouchView(touchView(controller), (
        offset: Offset.zero,
        scale: 1,
      ), 'custom wrapper discards queued default motion');
      disabled.value = false;
      await tester.pump();
      await first.moveBy(const Offset(40, 20));
      await _frames(tester);
      expect(
        controller.offset,
        Offset.zero,
        reason: 'held contacts cannot restart the new recognizer',
      );
      await first.up();
      await second.up();
      final fresh = await tester.startGesture(
        const Offset(200, 250),
        pointer: 3,
      );
      await fresh.moveBy(const Offset(100, 50));
      await fresh.up();
      await _frames(tester);
      expect(controller.offset, const Offset(-100, -50));
    },
  );
}
