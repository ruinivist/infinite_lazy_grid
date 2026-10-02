# infinite_lazy_grid

Infinite zoomable, pannable 2D canvas using spatial hash for only rendering what's visible.

Example: https://infinite-lazy-grid.pages.dev/

<p align='center'>
    <img loading="lazy" src="https://raw.githubusercontent.com/ruinivist/infinite_lazy_grid/main/demo.gif" />
</p>

## Quick Start

```dart
import 'package:flutter/material.dart';
import 'package:infinite_lazy_grid/infinite_lazy_grid.dart';

class DemoCanvas extends StatefulWidget {
  const DemoCanvas({super.key});
  @override
  State<DemoCanvas> createState() => _DemoCanvasState();
}

class _DemoCanvasState extends State<DemoCanvas> {
  // all interactions go through the controller
  final controller = LazyCanvasController(
    background: const DotGridBackground(),
    debug: true, // wraps each child with debug info visible on screen (positions, id)
  );

  @override
  void initState() {
    super.initState();
    // Add some sample nodes in a grid
    for (int i = 0; i < 50; i++) {
      controller.addChild(
        Offset((i % 10) * 140.0, (i ~/ 10) * 140.0),
        Container(
          width: 100,
          height: 100,
          color: Colors.primaries[i % Colors.primaries.length],
          alignment: Alignment.center,
          child: Text('${i + 1}', style: const TextStyle(color: Colors.white)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext ctx) {
    return Scaffold(
      appBar: AppBar(title: const Text('infinite_lazy_grid')),
      // pass the controller to the LazyCanvas widget
      body: LazyCanvas(controller: controller),
    );
  }
}
```

## Usage

### Adding/Removing children

```dart
// one child, returns its id which is just a uuid string
CanvasChildId oneChild = controller.addChild(
  const Offset(500, 1200),
  const Icon(Icons.place, size: 32),
);

// with custom widget
List<CanvasChildId> batchAdd = controller.addChildren([
  CanvasChildArgs(position: const Offset(0, 0), widget: const Text('Origin')),
  CanvasChildArgs(position: const Offset(800, 200), widget: const Icon(Icons.star)),
]);

// remove one by Id
controller.removeChild(oneChild);

// remove all
controller.clear();
```

### Focus / center

All of these animate by default (`duration` optional, `animate: false` to jump).

```dart
// child specific
controller.focusOnChild(id);                                   // keep scale
controller.focusOnChild(id, scalingMode: ScalingMode.resetScale);
controller.focusOnChild(id, scalingMode: ScalingMode.fitInViewport, preferredHorizontalMargin: 16);

// absolute position in grid space
controller.centerOnGridOffset(const Offset(0, 0));

// absolute position in screen space
controller.centerOnScreenOffset(const Offset(200, 150));
```

### Zoom & animate

```dart
controller.updateScalebyDelta(0.2);      // zoom in
controller.updateScalebyDelta(-0.2);     // zoom out
// animate to position on grid
await controller.animateToOffsetAndScale(
  offset: const Offset(1200, 300),
  scale: 2.0,
  duration: const Duration(milliseconds: 400),
);
```

Drag scrolling has inertia by default. Set `inertiaEnabled: false` to disable
it, or adjust `inertiaFrictionCoefficient` to tune how quickly it settles.

### Touch navigation and application tools

`LazyCanvas` defaults to one-finger touch navigation. For an editor where one
finger draws or moves an object, use `TouchNavigationMode.twoFinger`. Two or
more fingers then pan and pinch-zoom; stylus input stays available to tools.
Mouse navigation is controlled separately by `mousePanButtons`, and trackpad
and wheel navigation remain available in either touch mode.

The ownership callback fires synchronously when the second finger lands,
before the controller's raw down callback or any canvas transform. Cancel the
unfinished tool operation without committing it, and suppress tool input
while navigation owns the sequence:

```dart
bool touchNavigationActive = false;

void onToolPointerDown(PointerDownEvent event) {
  if (touchNavigationActive) return;
  // Start the application's tool operation.
}

LazyCanvas(
  controller: controller,
  touchNavigationMode: TouchNavigationMode.twoFinger,
  mousePanButtons: kSecondaryMouseButton | kMiddleMouseButton,
  onTouchNavigationChanged: (active) {
    touchNavigationActive = active;
    if (active) {
      // Discard the unfinished tool operation; clear its preview/pointer.
    }
  },
);
```

Apply the same guard to tool move/up handlers and child drag callbacks. Raw
pointer events still arrive, and child gesture recognizers are not canceled
automatically. Navigation can take over even after a child has won a drag.
Keep interrupted pointers suppressed through their final event dispatch:
ownership can become false before a child's final-up tap callback runs.

Use `viewportBuilder` to put floating object controls in the same gesture
region. An overlay outside `LazyCanvas` will not contribute touches:

```dart
viewportBuilder: (context, viewport) => Overlay.wrap(
  child: Stack(children: [viewport, objectControls]),
),
```

Keep the supplied viewport at the region's origin and original size. A local
`Overlay` also keeps descendant overlay portals in that gesture region.

When fewer than two fingers remain, the canvas freezes and ownership remains
active until **all** touches release or cancel. Adding another finger during
this release period does not restart navigation. No inertia starts at the end
of this two-finger sequence. Changing the mode during a touch sequence takes
effect on the next sequence.

The first touch stops existing viewport animation. Call
`controller.stopAnimation()` to stop inertia or an animated transition
explicitly without changing the current viewport.

### Background options

```dart
background: const NoBackground();
background: const SingleColorBackround(Colors.white);
background: const DotGridBackground(spacing: 60, size: 2.0);
```

All of these implement abstract class `CanvasBackground` so you can add your own.

### Render callbacks

```dart
LazyCanvasController(
  onWidgetEnteredRender: (id) { /* do something */ },
  onWidgetExitedRender: (id) { /* do something else */ },
);
```

### Widget updates

Since the args aren't directly available for you to place in the build tree, child rebuilds can be handled in three ways:

1. Stateful widget child: Child handles its own updates but state is lost when unmounted.
2. Manual update: `updateChildWidget(id, newWidget)`.
3. Child listens to external state: Some `Listenable` or a state management library like Provider, etc., that rebuilds the child when data changes.

### Size based optimisations

`focusOnChild` auto measures offstage if size unknown. Provide `childSize` if you already know it to skip the extra pass.

This extra pass is cached so would only happen once per child if size not provided.

## Example

See `example/` directory (Simple Example, Build Counts Example, Widget State Updates Example, Render Callbacks Example).
