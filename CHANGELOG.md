## 3.0.0

- **Breaking:** Remove `TouchNavigationMode` and the `touchNavigationMode` and
  `onTouchNavigationChanged` arguments from `LazyCanvas`. Touch drag and pinch
  now use Flutter's standard scale gesture recognizer.
- Add a read-only `overlappingChildren` query for rotated child layout rectangles.
- Fix culling for known-size children whose origins fall outside the build
  region by using their rotated layout bounds.
- Add `minHorizontalBuildPadding`, defaulting to 200 logical screen pixels per
  side. Values must be finite and nonnegative; use 0 to disable the minimum.

## 2.0.0

- **Breaking release.** See [migration notes](README.md#migrating-from-1x).
- Add rotation and stacking controls.
- Improve navigation and rendering.

## 1.0.0

-   Initial release

## 1.0.1

-   Update README

## 1.0.2

-   Again update README ( -\_-)

## 1.0.3

-   Update example

## 1.0.4

-   Add `hasChild` method to controller

## 1.0.5

-   Add inertial drag scrolling with configurable friction.
-   Fix child spatial index updates and removals.
-   Fix cache extent scaling and spatial query bounds.
-   Add animated package preview.
