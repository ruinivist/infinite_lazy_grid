// Verifies immutable snapshots and atomic child updates.
// Exercises the public controller and mounted Flutter child state.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_lazy_grid/infinite_lazy_grid.dart';

Future<void> initializeRenderQuery(LazyCanvasController controller) async {
  controller.onCanvasSizeChange(const Size(200, 200));
  await Future<void>.delayed(Duration.zero);
}

List<CanvasChildId> renderedIds(LazyCanvasController controller) => controller
    .widgetsWithScreenPositions(forceRebuild: true)
    .map((info) => info.id)
    .toList();

// ---------- Public API ----------

void main() {
  test(
    'snapshots are stable and combined updates notify after all fields change',
    () {
      final controller = LazyCanvasController();
      addTearDown(controller.dispose);
      const original = SizedBox(width: 80, height: 40);
      const replacement = SizedBox(width: 100, height: 60);
      final id = controller.addChild(const Offset(10, 20), original);
      final snapshot = controller.getInfo(id);
      expect(snapshot.child, same(original));
      expect(snapshot.childSize, isNull);
      expect(snapshot.rotation, 0);
      var notifications = 0;
      controller.addListener(() {
        notifications++;
        final info = controller.getInfo(id);
        expect(info.gsPosition, const Offset(30, 40));
        expect(info.rotation, 0.7);
        expect(info.childSize, const Size(100, 60));
        expect(info.child, same(replacement));
      });

      expect(
        controller.update(
          id,
          position: const Offset(30, 40),
          rotation: 0.7,
          childSize: const Size(100, 60),
          widget: replacement,
        ),
        isTrue,
      );
      expect(notifications, 1);
      expect(controller.update(id), isFalse);
      expect(
        controller.update(
          id,
          position: null,
          rotation: null,
          childSize: null,
          widget: null,
        ),
        isFalse,
      );
      expect(
        controller.update(
          id,
          position: const Offset(30, 40),
          rotation: 0.7,
          childSize: const Size(100, 60),
          widget: replacement,
        ),
        isFalse,
      );
      expect(notifications, 1);
      expect(snapshot.gsPosition, const Offset(10, 20));
      expect(snapshot.ssPosition, const Offset(10, 20));
      expect(snapshot.rotation, 0);
      expect(snapshot.childSize, isNull);
      expect(snapshot.child, same(original));
    },
  );

  test(
    'single-field updates preserve omitted fields and movement is batched',
    () {
      final controller = LazyCanvasController();
      addTearDown(controller.dispose);
      const original = SizedBox();
      const replacement = Text('replacement');
      final id = controller.addChild(
        const Offset(10, 20),
        original,
        childSize: const Size(80, 40),
      );
      var notifications = 0;
      controller.addListener(() => notifications++);

      expect(controller.update(id, position: const Offset(30, 40)), isTrue);
      expect(controller.getInfo(id).child, same(original));
      expect(controller.getInfo(id).childSize, const Size(80, 40));
      expect(controller.update(id, widget: replacement), isTrue);
      expect(controller.getInfo(id).gsPosition, const Offset(30, 40));
      expect(controller.getInfo(id).childSize, const Size(80, 40));
      expect(controller.update(id, childSize: Size.zero), isTrue);
      expect(controller.getInfo(id).gsPosition, const Offset(30, 40));
      expect(controller.getInfo(id).child, same(replacement));
      expect(controller.getInfo(id).childSize, Size.zero);
      expect(notifications, 3);

      controller.moveChildrenBy([id, id], const Offset(5, -5));
      expect(controller.getInfo(id).gsPosition, const Offset(35, 35));
      expect(notifications, 4);
      controller.moveChildrenBy([id], Offset.zero);
      controller.moveChildrenBy(const [], const Offset(10, 10));
      expect(controller.moveChildBy(id, Offset.zero), id);
      expect(notifications, 4);
    },
  );

  test('invalid inputs leave all fields and batch targets untouched', () {
    final controller = LazyCanvasController();
    addTearDown(controller.dispose);
    const original = SizedBox();
    final id = controller.addChild(
      Offset.zero,
      original,
      childSize: const Size(80, 40),
    );
    var notifications = 0;
    controller.addListener(() => notifications++);

    for (final size in [
      const Size(-1, 10),
      const Size(10, -1),
      const Size(double.nan, 10),
      const Size(10, double.infinity),
    ]) {
      expect(
        () => controller.update(
          id,
          position: const Offset(30, 40),
          rotation: 1,
          childSize: size,
          widget: const Text('changed'),
        ),
        throwsArgumentError,
      );
    }
    for (final position in [
      const Offset(double.infinity, 0),
      const Offset(0, double.nan),
    ]) {
      expect(
        () => controller.update(
          id,
          position: position,
          rotation: 1,
          childSize: Size.zero,
          widget: const Text('changed'),
        ),
        throwsArgumentError,
      );
    }
    expect(
      () => controller.moveChildrenBy([id, 'missing'], const Offset(10, 10)),
      throwsException,
    );
    expect(
      () => controller.moveChildrenBy([id], const Offset(double.nan, 0)),
      throwsArgumentError,
    );
    expect(
      () => controller.moveChildBy(id, const Offset(0, double.infinity)),
      throwsArgumentError,
    );
    expect(() => controller.update('missing'), throwsException);
    expect(() => controller.getInfo('missing'), throwsException);
    expect(
      () => controller.addChild(
        const Offset(double.infinity, 0),
        original,
        id: 'invalid',
      ),
      throwsArgumentError,
    );
    expect(controller.hasChild('invalid'), isFalse);
    expect(
      () => controller.addChildren([
        CanvasChildArgs(position: Offset.zero, widget: original, id: 'valid'),
        CanvasChildArgs(
          position: Offset.zero,
          widget: original,
          childSize: const Size(-1, 10),
        ),
      ]),
      throwsArgumentError,
    );
    expect(controller.hasChild('valid'), isFalse);
    final info = controller.getInfo(id);
    expect(info.gsPosition, Offset.zero);
    expect(info.rotation, 0);
    expect(info.childSize, const Size(80, 40));
    expect(info.child, same(original));
    expect(notifications, 0);
  });

  test('overflowing bounds leave adds and updates untouched', () async {
    const max = 1.7e308;
    final controller = LazyCanvasController();
    addTearDown(controller.dispose);
    const original = SizedBox(width: 20, height: 20);
    const peer = SizedBox(width: 20, height: 20);
    final id = controller.addChild(
      Offset.zero,
      original,
      childSize: const Size(20, 20),
      id: 'existing',
    );
    controller.addChild(
      const Offset(30, 0),
      peer,
      childSize: const Size(20, 20),
      id: 'peer',
    );
    await initializeRenderQuery(controller);
    final before = renderedIds(controller);
    final order = controller.childOrder;
    var notifications = 0;
    controller.addListener(() => notifications++);

    expect(
      () => controller.addChild(
        const Offset(max, 0),
        const Text('new'),
        childSize: const Size(max, 10),
        id: 'new',
      ),
      throwsArgumentError,
    );
    expect(
      () => controller.addChild(
        const Offset(max, 0),
        const Text('replacement'),
        childSize: const Size(max, 10),
        id: id,
      ),
      throwsArgumentError,
    );
    expect(
      () => controller.update(
        id,
        position: const Offset(max, 0),
        rotation: 0.5,
        childSize: const Size(max, 10),
        widget: const Text('updated'),
      ),
      throwsArgumentError,
    );

    final info = controller.getInfo(id);
    expect(info.gsPosition, Offset.zero);
    expect(info.rotation, 0);
    expect(info.childSize, const Size(20, 20));
    expect(info.child, same(original));
    expect(controller.getInfo('peer').child, same(peer));
    expect(controller.hasChild('new'), isFalse);
    expect(controller.childOrder, order);
    expect(renderedIds(controller), before);
    expect(notifications, 0);
  });

  test(
    'batch bounds overflow is rejected before any child is changed',
    () async {
      const max = 1.7e308;
      final controller = LazyCanvasController();
      addTearDown(controller.dispose);
      final existing = controller.addChild(Offset.zero, const SizedBox());
      await initializeRenderQuery(controller);
      final before = renderedIds(controller);
      final order = controller.childOrder;
      var notifications = 0;
      controller.addListener(() => notifications++);

      expect(
        () => controller.addChildren([
          CanvasChildArgs(
            position: const Offset(40, 40),
            widget: const SizedBox(),
            childSize: const Size(20, 20),
            id: 'valid',
          ),
          CanvasChildArgs(
            position: const Offset(max, 0),
            widget: const SizedBox(),
            childSize: const Size(max, 10),
            id: 'overflow',
          ),
        ], focusOnBuild: 'valid'),
        throwsArgumentError,
      );

      expect(controller.hasChild('valid'), isFalse);
      expect(controller.hasChild('overflow'), isFalse);
      expect(controller.childOrder, order);
      expect(controller.getInfo(existing).gsPosition, Offset.zero);
      expect(renderedIds(controller), before);
      expect(notifications, 0);
    },
  );

  test(
    'batch moves preflight finite positions with overflowing bounds',
    () async {
      const max = 1.7e308;
      final controller = LazyCanvasController(
        hashCellSize: const Size(max, max),
      );
      addTearDown(controller.dispose);
      final first = controller.addChild(
        Offset.zero,
        const SizedBox(),
        childSize: const Size(10, 10),
        id: 'first',
      );
      final large = controller.addChild(
        Offset.zero,
        const SizedBox(),
        childSize: const Size(max, 10),
        id: 'large',
      );
      await initializeRenderQuery(controller);
      final before = renderedIds(controller);
      final order = controller.childOrder;
      var notifications = 0;
      controller.addListener(() => notifications++);

      expect(
        () => controller.moveChildrenBy([first, large], const Offset(max, 0)),
        throwsArgumentError,
      );

      expect(controller.getInfo(first).gsPosition, Offset.zero);
      expect(controller.getInfo(large).gsPosition, Offset.zero);
      expect(controller.childOrder, order);
      expect(renderedIds(controller), before);
      expect(notifications, 0);
    },
  );

  test('overflowing measured bounds do not replace the cached size', () async {
    const max = 1.7e308;
    final controller = LazyCanvasController(hashCellSize: const Size(max, max));
    addTearDown(controller.dispose);
    final id = controller.addChild(
      const Offset(max, 0),
      const SizedBox(),
      childSize: Size.zero,
      id: 'measured',
    );
    await initializeRenderQuery(controller);
    final before = renderedIds(controller);
    var notifications = 0;
    controller.addListener(() => notifications++);

    expect(
      () => controller.onChildSizeChange(id, const Size(max, 10)),
      throwsArgumentError,
    );

    expect(controller.getInfo(id).childSize, Size.zero);
    expect(renderedIds(controller), before);
    expect(notifications, 0);
    controller.update(id, position: Offset.zero);
    expect(renderedIds(controller), [id]);
  });

  // ---------- Rendering ----------

  testWidgets(
    'culled snapshots include viewport coordinates without building',
    (tester) async {
      final controller = LazyCanvasController();
      var builds = 0;
      final child = Builder(
        builder: (_) {
          builds++;
          return const SizedBox(width: 80, height: 40);
        },
      );
      final id = controller.addChild(const Offset(5000, 5000), child);
      await tester.pumpWidget(
        MaterialApp(home: LazyCanvas(controller: controller)),
      );
      await tester.pumpAndSettle();
      controller.updateScalebyDelta(1, focalPoint: Offset.zero);
      controller.scrollBy(const Offset(20, 40));
      await tester.pumpAndSettle();
      final snapshot = controller.getInfo(id);
      expect(snapshot.gsPosition, const Offset(5000, 5000));
      expect(snapshot.ssPosition, const Offset(9980, 9960));
      expect(snapshot.childSize, isNull);
      expect(snapshot.child, same(child));
      expect(controller.update(id, childSize: const Size(80, 40)), isTrue);
      expect(controller.getInfo(id).childSize, const Size(80, 40));
      expect(snapshot.childSize, isNull);
      expect(builds, 0);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets(
    'geometry and compatible widget updates retain child state and focus',
    (tester) async {
      final controller = LazyCanvasController(debug: true);
      final focus = FocusNode();
      final text = TextEditingController(text: 'draft');
      const key = ValueKey('editor');
      Widget editor(String label, double width) => SizedBox(
        width: width,
        height: 60,
        child: TextField(
          key: key,
          focusNode: focus,
          controller: text,
          decoration: InputDecoration(labelText: label),
        ),
      );
      final id = controller.addChild(
        const Offset(100, 80),
        editor('first', 180),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: LazyCanvas(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();
      expect(controller.getInfo(id).childSize, const Size(180, 60));
      await tester.tap(find.byKey(key));
      await tester.pump();
      expect(focus.hasFocus, isTrue);
      final state = tester.state(find.byKey(key));

      controller.update(id, position: const Offset(120, 90), rotation: 0.7);
      await tester.pump();
      expect(tester.state(find.byKey(key)), same(state));
      final replacement = editor('second', 200);
      controller.update(id, widget: replacement);
      await tester.pump();
      expect(tester.state(find.byKey(key)), same(state));
      expect(focus.hasFocus, isTrue);
      expect(text.text, 'draft');
      final info = controller.getInfo(id);
      expect(info.gsPosition, const Offset(120, 90));
      expect(info.rotation, 0.7);
      expect(info.child, same(replacement));
      expect(info.childSize, const Size(200, 60));
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      text.dispose();
      focus.dispose();
    },
  );
}
