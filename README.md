# infinite_lazy_grid

Infinite zoomable, pannable 2D canvas using spatial hash for only rendering what's visible.

Example: https://infinite-lazy-grid.pages.dev/

## Deploying the example

`make deploy` builds the web example and deploys the current branch to Cloudflare Pages. Run `npx wrangler login` first to sign in. Only `main` updates the main demo; other branches get preview URLs. For example, `refactor/unify-navigation` deploys to https://refactor-unify-navigation.infinite-lazy-grid.pages.dev/.

The deployment workflow runs on every branch push and includes a deployment link in its job summary. Add `CLOUDFLARE_ACCOUNT_ID` and `CLOUDFLARE_API_TOKEN` to the repository's GitHub Actions secrets. The token needs **Account → Cloudflare Pages → Edit** for the account that owns `infinite-lazy-grid`. Branches need this workflow before pushes can trigger deployments.

Cloudflare keeps a stable branch URL pointing to that branch's latest deployment. See [preview deployments](https://developers.cloudflare.com/pages/configuration/preview-deployments/) for URL naming.

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

## Migrating from 1.x

Upgrade to `infinite_lazy_grid: ^2.0.0`:

- `updatePosition(id, position)` → `update(id, position: position)`.
- `updateChildWidget(id, widget)` → `update(id, widget: widget)`.
- `update()` now returns a boolean.
- Replace `buildCacheExtent`/`setBuildCacheExtent` with `buildExtentMultiplier` at construction. Default: twice the viewport.
- `ChildInfo` is now read-only ( as it should've been ). Its constructor needs `rotation` and nullable `childSize`. Its `child` is unwrapped.

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

### Arrange children

`childOrder` is an immutable back-to-front snapshot, including culled children.
Arrange moves IDs as one ordered bundle, ignoring duplicates.

```dart
final targets = [firstId, secondId];
controller.canArrange(targets, CanvasArrange.forward); // Check availability.
controller.bringForward(targets); // Cross the nearest overlap above the bundle.
controller.sendBackward(targets); // Cross the nearest overlap below the bundle.
controller.bringToFront(targets);
controller.sendToBack(targets);
```

Commands validate all IDs, return whether order changed, and notify once on change.
`canArrange` only checks. Forward/backward use rotated footprints and require
supplied or cached sizes, throwing `StateError` if unknown. Front/back need no sizes.

### Query overlapping children

```dart
final ids = controller.overlappingChildren(
  const Rect.fromLTWH(100, 200, 300, 150), // Canvas/grid coordinates.
);
```

Returns an immutable back-to-front snapshot using rotated layout rectangles,
including cached measurements of culled children. Unknown or empty sizes and
edge-only contact are excluded. Empty query rectangles return no IDs; nonfinite
bounds throw `ArgumentError`. The query does not build children, change order,
or notify listeners.

### Focus / center

All of these animate by default (`duration` optional, `animate: false` to jump).

```dart
// child specific
controller.focusOnChild(id);                                   // keep scale
controller.focusOnChild(id, scalingMode: ScalingMode.resetScale);
controller.focusOnChild(id, scalingMode: ScalingMode.fitInViewport, preferredHorizontalMargin: 16); // fit width and height

// absolute position in grid space
controller.centerOnGridOffset(const Offset(0, 0));

// absolute position in screen space
controller.centerOnScreenOffset(const Offset(200, 150));
```

### Zoom & animate

Set optional, read-only zoom limits when creating the controller:

```dart
final controller = LazyCanvasController(minScale: 0.25, maxScale: 4);
```

Omitted bounds are unrestricted. Supplied bounds must be finite and positive,
with `minScale <= maxScale`. The initial scale of `1`, gestures, zoom commands,
focus commands, and animations are clamped to the limits. Focus still centers
the child, but a minimum scale may prevent it from fitting fully in the viewport.

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

### Navigation

`LazyCanvas(controller: controller)` installs the default navigation: one-finger
pan, multi-finger pan and pinch zoom, primary-button mouse dragging, trackpad
pan and zoom, and wheel scrolling on both axes. Control-wheel and pointer-scale
signals zoom at the pointer. Stylus input remains available to application tools.

`mousePanButtons` selects the default mouse buttons. `onPointerScroll` replaces
ordinary wheel scrolling and receives the full screen-space delta. Nested
scrollables can consume signals before the canvas handles them.

Touch navigation uses Flutter's gesture thresholds and cooperates with child
gestures. It does not take over an object drag a child has already recognized.
Once navigation starts, movement has no additional dead zone. Adding or removing
contacts rebases without a viewport jump; remaining contacts continue navigating.
All participating contacts contribute to the centroid and pinch span.

Multi-contact updates are coordinated with display frames to prevent temporary
zoom pulses from separately delivered finger events. An incomplete sample waits
at most one extra frame; newer input cannot extend its deadline. Single-contact
panning does not wait for a partner. Zoom uses centroid anchoring even when one
finger stays still. Coincident contacts remain finite and continue panning.

Pure translation can end with inertia. Scaling or cancellation suppresses inertia
for that gesture. A new pointer stops viewport animation. Controller replacement
and disposal discard pending touch updates. `controller.stopAnimation()` stops
inertia or a programmed transition without changing the current viewport.

### Replace navigation

`navigationBuilder` replaces **all** default navigation. Returning its child alone
disables built-in touch, mouse, trackpad, wheel, and control-wheel navigation:

```dart
LazyCanvas(
  controller: controller,
  navigationBuilder: (context, child) => child,
)
```

Supply your own Flutter input widgets to drive the same controller:

```dart
LazyCanvas(
  controller: controller,
  navigationBuilder: (context, child) => GestureDetector(
    behavior: HitTestBehavior.translucent,
    onScaleStart: controller.onScaleStart,
    onScaleUpdate: controller.onScaleUpdate,
    onScaleEnd: controller.onScaleEnd,
    child: child,
  ),
)
```

This custom wrapper uses Flutter's scale recognition instead of grid's touch
sample coordination and supplies no wheel handling. Custom wrappers own gesture
recognition, interruption, and pointer signals; controller transforms still apply
zoom limits and inertia settings. `mousePanButtons` and `onPointerScroll` only
configure the default wrapper. Raw controller pointer callbacks remain observers
in either configuration and do not move the viewport themselves.

`TouchNavigationMode` and `onTouchNavigationChanged` have been removed. Editors
that need special takeover or release-locking rules must supply their own wrapper.

### Compose object controls

`viewportBuilder` composes the viewport before navigation wraps it, so overlays
share the same gesture region with both default and custom navigation:

```dart
viewportBuilder: (context, viewport) => Stack(
  children: [viewport, objectControls],
),
```

Keep the viewport at the region's origin and original size. An overlay outside
`LazyCanvas` is outside its navigation region. The example's Navigation page lets
you compare default, disabled, and custom gesture handling.

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
2. Manual update: `update(id, widget: newWidget)`.
3. Child listens to external state: Some `Listenable` or a state management library like Provider, etc., that rebuilds the child when data changes.

`getInfo(id)` returns an immutable snapshot of a child's position, widget and supplied or last-measured size, even when culled.

`update(id, position: position, childSize: size)` can update geometry too. Supplied fields apply together; omitted or null fields stay unchanged. Returns whether anything changed.

`update(id, rotation: angle)` rotates clockwise in radians around the layout center. `addChild` and `CanvasChildArgs` also accept `rotation` (default `0`); position and layout size stay unchanged.

### Size based optimisations

Children are culled by their unrotated top-left; `buildExtentMultiplier` controls the mounting buffer.

`focusOnChild` auto measures offstage if size unknown. Provide `childSize` if you already know it to skip the extra pass.

This extra pass is cached so would only happen once per child if size not provided.

## Example

See `example/` directory (Simple Example, Build Counts Example, Widget State Updates Example, Render Callbacks Example).
