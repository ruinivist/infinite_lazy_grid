// Verifies immutable snapshots and atomic child updates.
// Exercises the public controller and mounted Flutter child state.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_lazy_grid/infinite_lazy_grid.dart';

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
