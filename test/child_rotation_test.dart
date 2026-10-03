// Verifies child rotation, pointer coordinates and overlay transforms.
// Exercises the public controller and Flutter's rendering and overlay flows.
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_lazy_grid/infinite_lazy_grid.dart';

// ---------- Fixtures ----------

Future<void> pumpCanvas(
  WidgetTester tester,
  LazyCanvasController controller, {
  Size size = const Size(400, 300),
  Widget Function(BuildContext, Widget)? viewportBuilder,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Material(
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox.fromSize(
            size: size,
            child: LazyCanvas(
              controller: controller,
              mousePanButtons: kSecondaryMouseButton,
              viewportBuilder: viewportBuilder,
            ),
          ),
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

class LeftHalfPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.blue);
  }

  @override
  bool hitTest(Offset position) => position.dx < 50;

  @override
  bool shouldRepaint(LeftHalfPainter oldDelegate) => false;
}

void main() {
  // ---------- Rotation API ----------

  test(
    'rotation updates preserve omitted fields and reject nonfinite angles',
    () {
      final controller = LazyCanvasController();
      addTearDown(controller.dispose);
      const original = SizedBox(width: 80, height: 40);
      final id = controller.addChildren([
        CanvasChildArgs(
          position: const Offset(10, 20),
          widget: original,
          childSize: const Size(80, 40),
          rotation: 0.3,
        ),
      ]).single;
      expect(controller.getInfo(id).rotation, 0.3);
      var notifications = 0;
      controller.addListener(() => notifications++);
      expect(controller.update(id, rotation: 0.7), isTrue);
      final rotated = controller.getInfo(id);
      expect(rotated.gsPosition, const Offset(10, 20));
      expect(rotated.childSize, const Size(80, 40));
      expect(rotated.child, same(original));
      expect(controller.update(id, rotation: 0.7), isFalse);
      for (final angle in [
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        expect(
          () => controller.update(
            id,
            rotation: angle,
            position: Offset.zero,
            childSize: Size.zero,
            widget: const Text('changed'),
          ),
          throwsArgumentError,
        );
        expect(
          () => controller.addChild(Offset.zero, original, rotation: angle),
          throwsArgumentError,
        );
        expect(
          () => controller.addChildren([
            CanvasChildArgs(
              position: Offset.zero,
              widget: original,
              id: 'valid',
            ),
            CanvasChildArgs(
              position: Offset.zero,
              widget: original,
              rotation: angle,
            ),
          ]),
          throwsArgumentError,
        );
        expect(controller.hasChild('valid'), isFalse);
      }
      expect(controller.getInfo(id).gsPosition, rotated.gsPosition);
      expect(controller.getInfo(id).rotation, 0.7);
      expect(controller.getInfo(id).childSize, rotated.childSize);
      expect(controller.getInfo(id).child, same(original));
      expect(notifications, 1);
      controller.update(id, widget: const SizedBox(width: 120, height: 60));
      controller.moveChildBy(id, const Offset(10, 0));
      expect(controller.getInfo(id).rotation, 0.7);
      expect(notifications, 3);
    },
  );

  // ---------- Rendering and interaction ----------

  testWidgets(
    'paint and pointer transforms agree under rotation, pan and zoom',
    (tester) async {
      final controller = LazyCanvasController(background: const NoBackground());
      final captureKey = GlobalKey();
      const key = ValueKey('target');
      Offset? pointer;
      final id = controller.addChild(
        const Offset(100, 80),
        Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) => pointer = event.localPosition,
          child: const RepaintBoundary(
            child: ColoredBox(
              color: Colors.red,
              child: SizedBox(key: key, width: 100, height: 40),
            ),
          ),
        ),
        rotation: pi / 2,
      );
      await pumpCanvas(
        tester,
        controller,
        viewportBuilder: (_, viewport) =>
            RepaintBoundary(key: captureKey, child: viewport),
      );
      controller.updateScalebyDelta(1, focalPoint: Offset.zero);
      controller.scrollBy(const Offset(20, 10));
      await tester.pumpAndSettle();
      final box = tester.renderObject<RenderBox>(find.byKey(key));
      // Center (150,100) + clockwise rotation of local (-40,-10) => (160,60).
      const local = Offset(10, 10);
      const expected = Offset(300, 110);
      expectOffset(box.localToGlobal(local), expected);
      expectOffset(box.globalToLocal(expected), local);
      await tester.tapAt(expected);
      expectOffset(pointer!, local);
      expectOffset(controller.getInfo(id).ssPosition, const Offset(180, 150));
      expect(controller.getInfo(id).childSize, const Size(100, 40));
      final capture =
          captureKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      final pixels = await tester.runAsync(() async {
        final image = await capture.toImage(pixelRatio: 1);
        try {
          return await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        } finally {
          image.dispose();
        }
      });
      Color pixelAt(int x, int y) {
        final offset = (y * capture.size.width.toInt() + x) * 4;
        return Color.fromARGB(
          pixels!.getUint8(offset + 3),
          pixels.getUint8(offset),
          pixels.getUint8(offset + 1),
          pixels.getUint8(offset + 2),
        );
      }

      expect(pixelAt(300, 110).toARGB32(), Colors.red.toARGB32());
      expect(pixelAt(200, 110).a, 0);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets('delegates precise rotated hit tests and preserves stacking', (
    tester,
  ) async {
    final controller = LazyCanvasController();
    final hits = <String>[];
    Widget target(String name, {bool custom = false}) => Listener(
      onPointerDown: (_) => hits.add(name),
      child: custom
          ? CustomPaint(size: const Size(100, 40), painter: LeftHalfPainter())
          : const ColoredBox(
              color: Colors.red,
              child: SizedBox(width: 100, height: 40),
            ),
    );
    final back = controller.addChild(
      const Offset(100, 100),
      target('back'),
      rotation: pi / 2,
    );
    final front = controller.addChild(
      const Offset(100, 100),
      target('front', custom: true),
      rotation: pi / 2,
    );
    await pumpCanvas(tester, controller);
    await tester.tapAt(const Offset(150, 90)); // local (20,20)
    expect(hits, ['front']);
    hits.clear();
    await tester.tapAt(
      const Offset(150, 150),
    ); // local (80,20), custom target declines
    expect(hits, ['back']);
    controller.update(
      back,
      rotation: pi / 2 + 0.01,
      position: const Offset(101, 100),
    );
    await tester.pumpAndSettle();
    expect(controller.widgetsWithScreenPositions().map((info) => info.id), [
      back,
      front,
    ]);
    controller.bringToFront(back);
    await tester.pumpAndSettle();
    hits.clear();
    await tester.tapAt(const Offset(150, 90));
    expect(hits, ['back']);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets(
    'composited followers and portals follow the rotated local axes',
    (tester) async {
      final controller = LazyCanvasController();
      final link = LayerLink();
      final portal = OverlayPortalController();
      const leaderKey = ValueKey('leader');
      const followerKey = ValueKey('follower');
      const portalKey = ValueKey('portal');
      controller.addChild(
        const Offset(100, 80),
        CompositedTransformTarget(
          link: link,
          child: OverlayPortal(
            controller: portal,
            overlayChildBuilder: (context) => Positioned(
              left: 0,
              top: 0,
              child: CompositedTransformFollower(
                link: link,
                offset: const Offset(10, 10),
                child: const SizedBox(key: portalKey, width: 10, height: 10),
              ),
            ),
            child: const SizedBox(key: leaderKey, width: 100, height: 40),
          ),
        ),
        rotation: pi / 2,
      );
      await pumpCanvas(
        tester,
        controller,
        viewportBuilder: (context, viewport) => Overlay.wrap(
          child: Stack(
            children: [
              viewport,
              Positioned(
                left: 0,
                top: 0,
                child: CompositedTransformFollower(
                  link: link,
                  offset: const Offset(10, 10),
                  child: const SizedBox(
                    key: followerKey,
                    width: 10,
                    height: 10,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      portal.show();
      controller.updateScalebyDelta(0.5, focalPoint: Offset.zero);
      controller.scrollBy(const Offset(15, 15));
      await tester.pumpAndSettle();
      final leader = tester.renderObject<RenderBox>(find.byKey(leaderKey));
      final expected = leader.localToGlobal(const Offset(10, 10));
      for (final key in [followerKey, portalKey]) {
        final follower = tester.renderObject<RenderBox>(find.byKey(key));
        expectOffset(follower.localToGlobal(Offset.zero), expected);
        expectOffset(
          follower.localToGlobal(const Offset(5, 0)),
          leader.localToGlobal(const Offset(15, 10)),
        );
      }
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets('rotated scrollable consumes wheel input after pan and zoom', (
    tester,
  ) async {
    final controller = LazyCanvasController();
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    const key = ValueKey('scroll');
    controller.addChild(
      const Offset(100, 80),
      SizedBox(
        key: key,
        width: 160,
        height: 80,
        child: ListView(
          controller: scroll,
          children: const [SizedBox(height: 800)],
        ),
      ),
      rotation: pi / 4,
    );
    await pumpCanvas(tester, controller);
    controller.updateScalebyDelta(0.5, focalPoint: Offset.zero);
    controller.scrollBy(const Offset(15, 15));
    await tester.pumpAndSettle();
    final offset = controller.offset;
    final box = tester.renderObject<RenderBox>(find.byKey(key));
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: box.localToGlobal(const Offset(40, 20)),
        scrollDelta: const Offset(0, 40),
      ),
    );
    await tester.pump();
    expect(scroll.offset, greaterThan(0));
    expect(controller.offset, offset);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  // ---------- Focus and mounting ----------

  testWidgets(
    'focus centers rotated bounds and fits their limiting dimension',
    (tester) async {
      final controller = LazyCanvasController();
      final id = controller.addChild(
        const Offset(500, 600),
        const SizedBox(width: 100, height: 40),
        childSize: const Size(100, 40),
        rotation: pi / 2,
      );
      await pumpCanvas(tester, controller, size: const Size(300, 200));
      controller.focusOnChild(
        id,
        scalingMode: ScalingMode.fitInViewport,
        animate: false,
      );
      expect(controller.scale, closeTo(2, 1e-7));
      expectOffset(controller.offset, const Offset(475, 570));
      await tester.pumpAndSettle();
      controller.update(id, rotation: pi / 4);
      controller.focusOnChild(
        id,
        scalingMode: ScalingMode.fitInViewport,
        preferredHorizontalMargin: 20,
        animate: false,
      );
      expect(controller.scale, closeTo(200 / (140 / sqrt2), 1e-7));
      expectOffset(
        (const Offset(550, 620) - controller.offset) * controller.scale,
        const Offset(150, 100),
      );
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets('layout changes rotate around the newly measured center', (
    tester,
  ) async {
    final controller = LazyCanvasController();
    final sizes = ValueNotifier(const Size(100, 40));
    addTearDown(sizes.dispose);
    const key = ValueKey('resized');
    final id = controller.addChild(
      const Offset(100, 80),
      ValueListenableBuilder(
        valueListenable: sizes,
        builder: (_, size, _) => SizedBox.fromSize(key: key, size: size),
      ),
      rotation: pi / 2,
    );
    await pumpCanvas(tester, controller);
    sizes.value = const Size(120, 60);
    await tester.pumpAndSettle();
    final box = tester.renderObject<RenderBox>(find.byKey(key));
    expectOffset(box.localToGlobal(Offset.zero), const Offset(190, 50));
    expect(controller.getInfo(id).childSize, const Size(120, 60));
    controller.focusOnChild(id, animate: false);
    expectOffset(
      (const Offset(160, 110) - controller.offset) * controller.scale,
      const Offset(200, 150),
    );
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('rotation keeps mounting based on the unrotated top-left', (
    tester,
  ) async {
    final controller = LazyCanvasController(buildExtentMultiplier: 1);
    var builds = 0;
    final id = controller.addChild(
      const Offset(220, 50),
      Builder(
        builder: (_) {
          builds++;
          return const SizedBox(width: 40, height: 200);
        },
      ),
      childSize: const Size(40, 200),
      rotation: pi / 2,
    );
    await pumpCanvas(tester, controller, size: const Size(200, 200));
    // Rotated bounds overlap, but the origin is outside the build extent.
    expect(builds, 0);
    expect(controller.widgetsWithScreenPositions(), isEmpty);
    expect(controller.getInfo(id).rotation, pi / 2);
    controller.update(id, rotation: pi / 4, childSize: const Size(60, 200));
    await tester.pumpAndSettle();
    expect(builds, 0);
    controller.update(id, position: const Offset(160, 50));
    await tester.pumpAndSettle();
    expect(builds, 1);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
