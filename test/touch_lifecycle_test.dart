// Verifies touch sampling deadlines and navigation lifetime boundaries.
// Exercises grid ownership, queued motion, and cancellation without editor policy.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_lazy_grid/infinite_lazy_grid.dart';

import 'touch_test_helpers.dart';

// ---------- Frame deadlines and release ----------

void main() {
  const initial = (Offset(250, 340), Offset(490, 340));
  for (final hz in [60, 120]) {
    final interval = Duration(microseconds: (1000000 / hz).round());
    for (final canceled in [false, true]) {
      testWidgets(
        'queued motion survives ${canceled ? 'cancel' : 'release'} and stays frozen at $hz Hz',
        (tester) async {
          await pumpTouchCanvas(tester);
          final controller = _controller(tester);
          final start = touchView(controller);
          final first = await tester.startGesture(initial.$1, pointer: 1);
          final second = await tester.startGesture(initial.$2, pointer: 2);
          const delta = Offset(20, 10);
          await second.moveBy(delta);
          final target = stationaryTouchView(start, initial, (
            initial.$1,
            initial.$2 + delta,
          ));
          if (canceled) {
            await second.cancel();
          } else {
            await second.up();
          }
          await pumpTouchResponse(
            tester,
            previous: start,
            target: target,
            frameHz: hz,
          );
          await first.moveBy(const Offset(40, 20));
          await first.up();
          await pumpTouchHold(tester, expected: target, frameHz: hz);
        },
      );
    }

    testWidgets('a new lone update cannot renew an older deadline at $hz Hz', (
      tester,
    ) async {
      await pumpTouchCanvas(tester);
      final controller = _controller(tester);
      final start = touchView(controller);
      final first = await tester.startGesture(initial.$1, pointer: 1);
      final second = await tester.startGesture(initial.$2, pointer: 2);
      const delta = Offset(20, 10);
      await second.moveBy(delta);
      await tester.pump(interval);
      expectTouchView(
        touchView(controller),
        start,
        'the ambiguous first frame stays stable',
      );
      await second.moveBy(delta);
      final due = stationaryTouchView(start, initial, (
        initial.$1,
        initial.$2 + delta,
      ));
      await tester.pump(interval);
      final painted = paintedTouchLandmarks(tester);
      TouchMotionReport()
        ..sample(
          Duration.zero,
          painted,
          due,
          'old sample must respond despite newer input',
        )
        ..verify();
      final target = stationaryTouchView(start, initial, (
        initial.$1,
        initial.$2 + delta * 2,
      ));
      await pumpTouchResponse(
        tester,
        previous: due,
        target: target,
        frameHz: hz,
      );
      await first.up();
      await second.up();
    });

    testWidgets(
      'completed pair is preserved beside a newer partial sample at $hz Hz',
      (tester) async {
        await pumpTouchCanvas(tester);
        final controller = _controller(tester);
        final start = touchView(controller);
        final first = await tester.startGesture(initial.$1, pointer: 1);
        final second = await tester.startGesture(initial.$2, pointer: 2);
        const delta = Offset(20, 10);
        await first.moveBy(delta);
        await second.moveBy(delta);
        await first.moveBy(delta);
        final paired = (
          offset: start.offset - delta / start.scale,
          scale: start.scale,
        );
        await tester.pump(interval);
        TouchMotionReport()
          ..sample(
            Duration.zero,
            paintedTouchLandmarks(tester),
            paired,
            'never render the newer half-pan',
          )
          ..verify();
        await second.moveBy(delta);
        final target = (
          offset: start.offset - delta * 2 / start.scale,
          scale: start.scale,
        );
        await pumpTouchResponse(
          tester,
          previous: paired,
          target: target,
          frameHz: hz,
        );
        await first.up();
        await second.up();
        await pumpTouchHold(tester, expected: target, frameHz: hz);
      },
    );
  }

  for (final hz in [60, 120]) {
    for (final canceled in [false, true]) {
      for (final corrupt in [false, true]) {
        testWidgets(
          '${canceled ? 'canceled' : 'held'} touches ${corrupt ? 'reject restored drift' : 'stay stable'} for 200ms at $hz Hz',
          (tester) async {
            await pumpTouchCanvas(tester);
            final controller = _controller(tester);
            final start = touchView(controller);
            final first = await tester.startGesture(initial.$1, pointer: 1);
            final second = await tester.startGesture(initial.$2, pointer: 2);
            const delta = Offset(20, 10);
            await first.moveBy(delta);
            await second.moveBy(delta);
            final frozen = (
              offset: start.offset - delta / start.scale,
              scale: start.scale,
            );
            await pumpTouchResponse(
              tester,
              previous: start,
              target: frozen,
              frameHz: hz,
            );
            if (canceled) {
              await first.cancel();
              await second.cancel();
            }
            if (corrupt) {
              Timer(
                const Duration(milliseconds: 40),
                () => controller.scrollBy(const Offset(0, 20)),
              );
              Timer(
                const Duration(milliseconds: 140),
                () => controller.scrollBy(const Offset(0, -20)),
              );
            }
            TestFailure? failure;
            try {
              await pumpTouchHold(tester, expected: frozen, frameHz: hz);
            } on TestFailure catch (error) {
              failure = error;
            }
            if (corrupt) {
              expect(failure, isA<TestFailure>());
              final observed = RegExp(
                r'at (\d+)us',
              ).firstMatch(failure?.message ?? '');
              expect(observed, isNotNull);
              expect(
                int.parse(observed!.group(1)!),
                inInclusiveRange(40000, 140000),
              );
            } else {
              expect(failure, isNull);
            }
            TouchMotionReport()
              ..sample(
                Duration.zero,
                paintedTouchLandmarks(tester),
                frozen,
                'correct endpoint',
              )
              ..verify();
            if (!canceled) {
              await first.up();
              await second.up();
            }
          },
        );
      }
    }
  }

  for (final hz in [60, 120]) {
    testWidgets(
      'stationary and moving anchors transition continuously at $hz Hz',
      (tester) async {
        await pumpTouchCanvas(tester);
        final controller = _controller(tester);
        final start = touchView(controller);
        final first = await tester.startGesture(initial.$1, pointer: 1);
        final second = await tester.startGesture(initial.$2, pointer: 2);
        final spread = (initial.$1, initial.$2 + const Offset(40, 20));
        await second.moveTo(spread.$2);
        final anchoredFirst = stationaryTouchView(start, initial, spread);
        await pumpTouchResponse(
          tester,
          previous: start,
          target: anchoredFirst,
          frameHz: hz,
        );
        await pumpTouchHold(tester, expected: anchoredFirst, frameHz: hz);

        const pan = Offset(30, -10);
        final moving = (
          spread.$1 + pan - const Offset(10, 0),
          spread.$2 + pan + const Offset(10, 0),
        );
        final beforeCenter = (spread.$1 + spread.$2) / 2;
        final center = (moving.$1 + moving.$2) / 2;
        final centerWorld =
            anchoredFirst.offset + beforeCenter / anchoredFirst.scale;
        final movingScale =
            start.scale *
            (moving.$2 - moving.$1).distance /
            (initial.$2 - initial.$1).distance;
        final centered = (
          offset: centerWorld - center / movingScale,
          scale: movingScale,
        );
        await first.moveTo(moving.$1);
        await second.moveTo(moving.$2);
        await pumpTouchResponse(
          tester,
          previous: anchoredFirst,
          target: centered,
          frameHz: hz,
        );
        await pumpTouchHold(tester, expected: centered, frameHz: hz);

        final finalFirst = moving.$1 + const Offset(-30, 10);
        final secondWorld = centered.offset + moving.$2 / centered.scale;
        final finalScale =
            start.scale *
            (moving.$2 - finalFirst).distance /
            (initial.$2 - initial.$1).distance;
        final anchoredSecond = (
          offset: secondWorld - moving.$2 / finalScale,
          scale: finalScale,
        );
        await first.moveTo(finalFirst);
        await pumpTouchResponse(
          tester,
          previous: centered,
          target: anchoredSecond,
          frameHz: hz,
        );
        await second.up();
        await first.up();
        await pumpTouchHold(tester, expected: anchoredSecond, frameHz: hz);
      },
    );
  }

  // ---------- Fixed pair and lifetime ----------

  for (final removed in [0, 1]) {
    testWidgets(
      'extra contacts are ignored and never replace original finger ${removed + 1}',
      (tester) async {
        await pumpTouchCanvas(tester);
        final controller = _controller(tester);
        final start = touchView(controller);
        final fingers = [
          await tester.startGesture(initial.$1, pointer: 1),
          await tester.startGesture(initial.$2, pointer: 2),
        ];
        final extra = await tester.startGesture(
          const Offset(600, 450),
          pointer: 3,
        );
        await extra.moveBy(const Offset(100, -30));
        await pumpTouchHold(tester, expected: start);
        const delta = Offset(20, 10);
        await fingers[0].moveBy(delta);
        await fingers[1].moveBy(delta);
        final target = (
          offset: start.offset - delta / start.scale,
          scale: start.scale,
        );
        await pumpTouchResponse(tester, previous: start, target: target);
        await fingers[removed].up();
        await fingers[1 - removed].moveBy(delta);
        await extra.moveBy(delta);
        await pumpTouchHold(tester, expected: target);
        await fingers[1 - removed].up();
        await extra.up();
        await pumpTouchHold(tester, expected: target);
      },
    );
  }

  testWidgets(
    'lifting an ignored contact leaves the original pair in control',
    (tester) async {
      await pumpTouchCanvas(tester);
      final controller = _controller(tester);
      final start = touchView(controller);
      final first = await tester.startGesture(initial.$1, pointer: 1);
      final second = await tester.startGesture(initial.$2, pointer: 2);
      final extra = await tester.startGesture(
        const Offset(600, 450),
        pointer: 3,
      );
      await extra.cancel();
      const delta = Offset(20, 10);
      await first.moveBy(delta);
      await second.moveBy(delta);
      final target = (
        offset: start.offset - delta / start.scale,
        scale: start.scale,
      );
      await pumpTouchResponse(tester, previous: start, target: target);
      await first.up();
      await second.up();
    },
  );

  testWidgets(
    'controller replacement discards queued motion and drains held fingers',
    (tester) async {
      final old = LazyCanvasController(
        minScale: 0.5,
        maxScale: 2,
        buildExtentMultiplier: 3.4,
      );
      await pumpTouchCanvas(tester, controller: old);
      final first = await tester.startGesture(initial.$1, pointer: 1);
      final second = await tester.startGesture(initial.$2, pointer: 2);
      await second.moveBy(const Offset(30, 20));
      final replacement = LazyCanvasController(
        minScale: 0.5,
        maxScale: 2,
        buildExtentMultiplier: 3.4,
      );
      await pumpTouchCanvas(tester, controller: replacement);
      final target = touchView(replacement);
      expectTouchView(touchView(old), (
        offset: Offset.zero,
        scale: 1,
      ), 'queued edits cannot reach detached controller');
      await first.moveBy(const Offset(20, 10));
      await second.moveBy(const Offset(20, 10));
      await first.up();
      await second.up();
      await pumpTouchHold(tester, expected: target);
      expectTouchView(touchView(old), (
        offset: Offset.zero,
        scale: 1,
      ), 'no late writes to detached controller');
      final fresh = await tester.startGesture(initial.$1, pointer: 3);
      final partner = await tester.startGesture(initial.$2, pointer: 4);
      const delta = Offset(20, 10);
      await fresh.moveBy(delta);
      await partner.moveBy(delta);
      await pumpTouchResponse(
        tester,
        previous: target,
        target: (
          offset: target.offset - delta / target.scale,
          scale: target.scale,
        ),
      );
      await fresh.up();
      await partner.up();
    },
  );

  testWidgets('disposal cancels pending frame callbacks', (tester) async {
    await pumpTouchCanvas(tester);
    final controller = _controller(tester);
    final first = await tester.startGesture(initial.$1, pointer: 1);
    final second = await tester.startGesture(initial.$2, pointer: 2);
    await second.moveBy(const Offset(30, 20));
    final start = touchView(controller);
    await tester.pumpWidget(const SizedBox());
    await first.up();
    await second.up();
    await tester.pump(const Duration(milliseconds: 200));
    expectTouchView(
      touchView(controller),
      start,
      'disposed navigation must not mutate the controller',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'coincident fingers remain finite without a configured zoom minimum',
    (tester) async {
      final controller = LazyCanvasController(buildExtentMultiplier: 3.4);
      await pumpTouchCanvas(tester, controller: controller);
      final first = await tester.startGesture(initial.$1, pointer: 1);
      final second = await tester.startGesture(initial.$2, pointer: 2);
      final start = touchView(controller);
      await first.moveTo(const Offset(370, 340));
      await second.moveTo(const Offset(370, 340));
      await pumpTouchResponse(tester, previous: start, target: start);
      expect(controller.scale.isFinite, isTrue);
      expect(controller.scale, isPositive);
      await first.moveTo(initial.$1);
      await second.moveTo(initial.$2);
      await pumpTouchResponse(tester, previous: start, target: start);
      await first.up();
      await second.up();
    },
  );
}

// ---------- View access ----------

LazyCanvasController _controller(WidgetTester tester) =>
    tester.widget<LazyCanvas>(find.byType(LazyCanvas)).controller;
