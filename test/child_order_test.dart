// Verifies bundle ordering and atomic Arrange commands.
// Exercises the public controller and Flutter paint, pointer and state flows.
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
    SizedBox.fromSize(size: size ?? const Size(100, 100)),
    id: id,
    childSize: size,
    rotation: rotation,
  );
}

bool arrange(
  LazyCanvasController controller,
  Iterable<CanvasChildId> ids,
  CanvasArrange action,
) => switch (action) {
  CanvasArrange.forward => controller.bringForward(ids),
  CanvasArrange.backward => controller.sendBackward(ids),
  CanvasArrange.front => controller.bringToFront(ids),
  CanvasArrange.back => controller.sendToBack(ids),
};

Future<void> pumpCanvas(
  WidgetTester tester,
  LazyCanvasController controller, {
  GlobalKey? captureKey,
  CanvasChildId? foregroundChildId,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 400,
          height: 300,
          child: LazyCanvas(
            controller: controller,
            foregroundChildId: foregroundChildId,
            mousePanButtons: kSecondaryMouseButton,
            viewportBuilder: captureKey == null
                ? null
                : (_, viewport) =>
                      RepaintBoundary(key: captureKey, child: viewport),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

// ---------- Ordering and validation ----------

void main() {
  for (final action in CanvasArrange.values) {
    test('$action moves a noncontiguous bundle atomically in stack order', () {
      final controller = LazyCanvasController();
      addTearDown(controller.dispose);
      for (final id in ['a', 'b', 'c', 'd', 'e']) {
        addChild(controller, id);
      }
      final snapshot = controller.childOrder;
      final expected =
          action == CanvasArrange.forward || action == CanvasArrange.front
          ? ['a', 'c', 'e', 'b', 'd']
          : ['b', 'd', 'a', 'c', 'e'];
      var notifications = 0;
      controller.addListener(() {
        notifications++;
        expect(controller.childOrder, expected);
      });
      const targets = ['d', 'b', 'd'];
      expect(controller.canArrange(targets, action), isTrue);
      expect(controller.childOrder, snapshot);
      expect(notifications, 0);
      expect(arrange(controller, targets, action), isTrue);
      expect(controller.childOrder, expected);
      expect(notifications, 1);
      expect(snapshot, ['a', 'b', 'c', 'd', 'e']);
      expect(() => snapshot.add('extra'), throwsUnsupportedError);
      expect(() => snapshot[0] = 'extra', throwsUnsupportedError);
      expect(controller.canArrange(targets, action), isFalse);
      expect(arrange(controller, targets, action), isFalse);
      expect(notifications, 1);
    });

    test('$action validates every ID and does not notify on no-ops', () {
      final controller = LazyCanvasController();
      addTearDown(controller.dispose);
      addChild(controller, 'a');
      addChild(controller, 'b');
      var notifications = 0;
      controller.addListener(() => notifications++);
      for (final ids in [
        <String>[],
        ['b', 'a', 'b'],
      ]) {
        expect(controller.canArrange(ids, action), isFalse);
        expect(arrange(controller, ids, action), isFalse);
      }
      expect(
        () => controller.canArrange(['a', 'missing'], action),
        throwsException,
      );
      expect(
        () => arrange(controller, ['a', 'missing'], action),
        throwsException,
      );
      expect(controller.childOrder, ['a', 'b']);
      expect(notifications, 0);
    });
  }

  test('forward and backward skip nonoverlaps and cross only the nearest', () {
    final controller = LazyCanvasController();
    addTearDown(controller.dispose);
    for (final id in ['a', 'b', 'c', 'd', 'e', 'f']) {
      addChild(
        controller,
        id,
        position: ['b', 'd'].contains(id) ? const Offset(1000, 0) : Offset.zero,
      );
    }
    expect(controller.bringForward(['c']), isTrue);
    expect(controller.childOrder, ['a', 'b', 'd', 'e', 'c', 'f']);
    expect(controller.sendBackward(['c']), isTrue);
    expect(controller.childOrder, ['a', 'b', 'd', 'c', 'e', 'f']);
    expect(controller.sendBackward(['c']), isTrue);
    expect(controller.childOrder, ['c', 'a', 'b', 'd', 'e', 'f']);
  });

  test('overlap uses every bundle member beyond its outer boundary', () {
    final controller = LazyCanvasController();
    addTearDown(controller.dispose);
    addChild(controller, 'a');
    addChild(controller, 'b'); // Internal overlap must not be crossed.
    addChild(controller, 'c', position: const Offset(1000, 0));
    addChild(controller, 'd'); // Overlaps a, not the frontmost target c.
    addChild(controller, 'e');
    expect(controller.bringForward(['c', 'a']), isTrue);
    expect(controller.childOrder, ['b', 'd', 'a', 'c', 'e']);
    expect(controller.sendBackward(['c', 'a']), isTrue);
    expect(controller.childOrder, ['b', 'a', 'c', 'd', 'e']);
  });

  test(
    'rotated footprints reject bounding-box overlap and include rotation',
    () {
      final controller = LazyCanvasController();
      addTearDown(controller.dispose);
      addChild(controller, 'a', size: const Size(100, 10), rotation: pi / 4);
      addChild(
        controller,
        'b',
        position: const Offset(12, 30),
        size: const Size(5, 5),
      ); // Inside the rotated bounding box but outside the rectangle.
      addChild(
        controller,
        'c',
        position: const Offset(76, 29),
        size: const Size(5, 5),
      ); // Inside the rotated rectangle, outside the unrotated one.
      expect(controller.bringForward(['a']), isTrue);
      expect(controller.childOrder, ['b', 'c', 'a']);
      expect(controller.sendBackward(['a']), isTrue);
      expect(controller.childOrder, ['b', 'a', 'c']);
      expect(controller.canArrange(['a'], CanvasArrange.backward), isFalse);
    },
  );

  test('disjoint, touching and zero-area footprints do not change order', () {
    final controller = LazyCanvasController();
    addTearDown(controller.dispose);
    addChild(controller, 'a');
    addChild(controller, 'b', position: const Offset(100, 0));
    addChild(controller, 'c', size: Size.zero);
    var notifications = 0;
    controller.addListener(() => notifications++);
    expect(controller.canArrange(['a'], CanvasArrange.forward), isFalse);
    expect(controller.bringForward(['a']), isFalse);
    expect(controller.sendBackward(['b']), isFalse);
    expect(controller.childOrder, ['a', 'b', 'c']);
    expect(notifications, 0);
  });

  test('unknown required target or candidate sizes reject before mutation', () {
    final controller = LazyCanvasController();
    addTearDown(controller.dispose);
    addChild(controller, 'a');
    addChild(controller, 'unknown', size: null);
    addChild(controller, 'c');
    var notifications = 0;
    controller.addListener(() => notifications++);
    final error = throwsA(
      isA<StateError>().having(
        (error) => error.message,
        'child ID',
        contains('unknown'),
      ),
    );
    for (final (ids, action) in [
      (['a'], CanvasArrange.forward),
      (['c'], CanvasArrange.backward),
      (['unknown'], CanvasArrange.forward),
      (['unknown'], CanvasArrange.backward),
      (['a', 'unknown'], CanvasArrange.forward),
    ]) {
      expect(() => controller.canArrange(ids, action), error);
      expect(() => arrange(controller, ids, action), error);
      expect(controller.childOrder, ['a', 'unknown', 'c']);
      expect(controller.getInfo('unknown').childSize, isNull);
      expect(notifications, 0);
    }
    expect(controller.bringToFront(['unknown']), isTrue);
    expect(controller.sendToBack(['unknown']), isTrue);
    expect(notifications, 2);
    // No overlap measurement is needed at the edge of the stack.
    expect(controller.sendBackward(['unknown']), isFalse);
    controller.update('unknown', childSize: const Size(100, 100));
    expect(controller.bringForward(['unknown']), isTrue);
  });

  test('adding, removing and clearing preserve stack lifecycle', () {
    final controller = LazyCanvasController();
    addTearDown(controller.dispose);
    addChild(controller, 'a', size: null);
    addChild(controller, 'b', size: null);
    addChild(controller, 'c', size: null);
    controller.sendToBack(['c']);
    controller.removeChild('a');
    addChild(controller, 'd');
    expect(controller.childOrder, ['c', 'b', 'd']);
    controller.bringToFront(['c']);
    addChild(controller, 'e');
    expect(controller.childOrder, ['b', 'd', 'c', 'e']);
    controller.clear();
    expect(controller.childOrder, isEmpty);
    for (final action in CanvasArrange.values) {
      expect(controller.canArrange([], action), isFalse);
      expect(arrange(controller, [], action), isFalse);
    }
    addChild(controller, 'a');
    addChild(controller, 'b');
    expect(controller.childOrder, ['a', 'b']);
  });

  // ---------- Rendering and retained measurements ----------

  testWidgets(
    'culled children retain layout sizes and participate in Arrange',
    (tester) async {
      final controller = LazyCanvasController(buildExtentMultiplier: 1);
      addChild(controller, 'a', size: null);
      addChild(controller, 'b', size: null);
      await pumpCanvas(tester, controller);
      expect(controller.getInfo('a').childSize, const Size(100, 100));
      controller.scrollBy(const Offset(5000, 5000));
      await tester.pumpAndSettle();
      expect(controller.widgetsWithScreenPositions(), isEmpty);
      expect(controller.childOrder, ['a', 'b']);
      expect(controller.canArrange(['a'], CanvasArrange.forward), isTrue);
      expect(controller.bringForward(['a']), isTrue);
      expect(controller.childOrder, ['b', 'a']);
      expect(controller.getInfo('a').childSize, const Size(100, 100));
      expect(controller.widgetsWithScreenPositions(), isEmpty);
      controller.scrollBy(const Offset(-5000, -5000));
      await tester.pumpAndSettle();
      expect(controller.widgetsWithScreenPositions().map((info) => info.id), [
        'b',
        'a',
      ]);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets(
    'foreground and Arrange preserve state with matching paint and hit order',
    (tester) async {
      final controller = LazyCanvasController(background: const NoBackground());
      final captureKey = GlobalKey();
      const stateKey = ValueKey('state');
      var count = 0;
      String? hit;
      final a = controller.addChild(
        const Offset(50, 50),
        StatefulBuilder(
          key: stateKey,
          builder: (_, setState) {
            return GestureDetector(
              onTap: () => setState(() {
                hit = 'a';
                count++;
              }),
              child: ColoredBox(
                color: Colors.red,
                child: SizedBox(width: 100, height: 100, child: Text('$count')),
              ),
            );
          },
        ),
        rotation: pi / 4,
      );
      final b = controller.addChild(
        const Offset(50, 50),
        GestureDetector(
          onTap: () => hit = 'b',
          child: const RepaintBoundary(
            child: ColoredBox(
              color: Colors.blue,
              child: SizedBox(width: 100, height: 100),
            ),
          ),
        ),
        rotation: pi / 4,
      );
      await pumpCanvas(tester, controller, captureKey: captureKey);
      final state = tester.state(find.byKey(stateKey));
      final snapshots = [controller.getInfo(a), controller.getInfo(b)];

      Future<void> expectTop(String id, Color color) async {
        await tester.tapAt(const Offset(110, 110));
        await tester.pumpAndSettle();
        expect(hit, id);
        expect(tester.state(find.byKey(stateKey)), same(state));
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
        final offset = (110 * capture.size.width.toInt() + 110) * 4;
        expect(
          Color.fromARGB(
            pixels!.getUint8(offset + 3),
            pixels.getUint8(offset),
            pixels.getUint8(offset + 1),
            pixels.getUint8(offset + 2),
          ).toARGB32(),
          color.toARGB32(),
        );
      }

      await expectTop('b', Colors.blue);
      var notifications = 0;
      controller.addListener(() => notifications++);
      for (final (foreground, top, color) in [
        (a, 'a', Colors.red),
        (b, 'b', Colors.blue),
        ('missing', 'b', Colors.blue),
        (a, 'a', Colors.red),
        (null, 'b', Colors.blue),
      ]) {
        await pumpCanvas(
          tester,
          controller,
          captureKey: captureKey,
          foregroundChildId: foreground,
        );
        await expectTop(top, color);
        expect(controller.childOrder, [a, b]);
        expect(controller.widgetsWithScreenPositions().map((info) => info.id), [
          a,
          b,
        ]);
        expect(notifications, 0);
        expect(controller.canArrange([a], CanvasArrange.forward), isTrue);
      }
      for (final (action, id, color) in [
        (CanvasArrange.forward, 'a', Colors.red),
        (CanvasArrange.backward, 'b', Colors.blue),
        (CanvasArrange.front, 'a', Colors.red),
        (CanvasArrange.back, 'b', Colors.blue),
      ]) {
        expect(arrange(controller, [a], action), isTrue);
        await tester.pumpAndSettle();
        await expectTop(id, color);
      }
      expect(count, 4);
      for (final snapshot in snapshots) {
        final info = controller.getInfo(snapshot.id);
        expect(info.gsPosition, snapshot.gsPosition);
        expect(info.childSize, snapshot.childSize);
        expect(info.rotation, snapshot.rotation);
        expect(info.child, same(snapshot.child));
      }
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
}
