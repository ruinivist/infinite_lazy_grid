# Navigation refactor plan

## Goal and scope

Give `LazyCanvas` conventional navigation defaults and one escape hatch for custom input. Fix jittery translation during pinch zoom in shared touch handling. Breaking API changes are allowed. Application migration, including Elseplane, is separate work.

The rollback baseline retained the stabilization tests while restoring the earlier implementation. Its focused Chrome run produced 78 passes and 46 failures. Those failures mixed motion defects with expectations about editor-specific gesture policies.

## Library boundary

| Component | Owns |
| --- | --- |
| `LazyCanvas` | Viewport composition, lazy rendering, layout, painting, hit testing, and controller attachment |
| Default navigation wrapper | Gesture recognition, contact tracking, sample coordination, pointer signals, and navigation lifetime |
| `LazyCanvasController` | Viewport transforms, coordinate conversion, zoom limits, animation, and inertia |
| Custom navigation wrapper | Its own recognition, application interruption rules, and pointer signals, using controller operations |

Grid does not provide forced child-drag takeover, fixed finger pairs, release locking, or stationary-finger anchoring policies. Applications requiring those behaviors replace the navigation wrapper. There is no public policy framework or smoothing configuration.

## API and composition

`navigationBuilder` has type `Widget Function(BuildContext context, Widget child)?`:

- Omitted: install the default navigation wrapper.
- Supplied: replace all default touch, mouse, trackpad, wheel, and control-wheel navigation.
- Returning `child` unchanged disables built-in navigation.

The child includes `viewportBuilder` content, so composed controls share the navigation region. Raw controller pointer callbacks remain outside the wrapper as observers; they fire once and do not move the viewport. `mousePanButtons` and `onPointerScroll` configure only the default wrapper. Existing controller scale, scroll, animation, and inertia methods remain available to custom Flutter gesture handlers.

Remove `TouchNavigationMode` and `onTouchNavigationChanged`. Custom gesture recognition does not inherit grid's internal sample coordination. This is an intentional consequence of full replacement, documented in the README and demonstrated by the Navigation example.

## Default motion

One touch pans; multiple participating touches pan and pinch together. Recognition uses Flutter's thresholds and normal gesture arbitration. A winning child keeps its gesture. Qualifying movement includes the full displacement, and recognized movement has no additional dead zone.

All participating contacts contribute to the centroid and mean radius. Adding or removing a contact rebases without moving the viewport; survivors and replacement contacts can continue. Centroid anchoring applies even when a finger stays still. Mouse-button, trackpad, and stylus defaults remain consistent with the previous API. Ordinary wheel input preserves both axes.

Use one touch recognizer in `lib/core/navigation.dart`. Device adapters may differ, but all use the controller's existing combined pan/scale transform operations. Keep the recognizers and sampling helpers private.

Coordinate multi-contact snapshots on display frames. Group updates from distinct contacts; a repeated contact begins a new snapshot. Complete snapshots can apply on the next frame. Incomplete snapshots wait at most one additional frame, and newer input cannot renew an older deadline. Apply the newest eligible snapshot while retaining newer incomplete input. Single-contact movement needs no partner wait.

Flush received motion before contact-set changes, normal release, or cancellation. Preserve usable pinch references through coincident contacts; with no minimum scale, keep the last positive scale while continuing translation. Initially coincident contacts establish a span without a zoom jump. Apply clamping and panning together in local coordinates.

Pure translation may end with inertia. Any scaling or cancellation suppresses inertia for that gesture. Track cumulative translation for velocity so contact changes cannot manufacture a fling. A new pointer stops animation. Controller replacement and disposal discard queued work; held pointers cannot continue the detached recognizer.

## Test migration

Keep the independent geometry oracle, rendered landmark checks, negative controls, input order variations, and 60/120 Hz frame schedules. Correct endpoints do not establish stable intermediate motion. Do not loosen geometry tolerances or skip failing assertions.

| Previous coverage | Replacement or retained behavior |
| --- | --- |
| Pan/pinch timing, subpixel motion, zoom limits, coincidence, and rotation | Retain against default navigation, establishing recognition before motion-only traces |
| Stationary-finger and diagonal traces | Retain the input traces with centroid-based expected geometry |
| Stationary-anchor drift negative control | Detect incorrect centroid geometry despite a correct endpoint |
| Fixed pair, ignored contacts, and drain-until-release | Verify continuous one/two/three-contact transitions, cancellation, and replacement contacts without jumps |
| Forced takeover after a child wins | Verify that a winning child keeps its drag |
| Mode changes during a held sequence | Verify default-wrapper replacement, disabling, and controller replacement without stale input |
| Overlay navigation region | Verify both default and custom wrappers receive composed content |
| Wheel and raw callbacks | Verify both-axis scrolling, replacement handlers, child consumption, and exactly-once observation |
| Custom navigation | Verify custom transforms/signals and absence of every default input path with an identity wrapper |
| Inertia | Verify normal translation, contact rebasing, cancellation, and scaling behavior |

The old count of 124 tests is not an acceptance target. Each changed policy assertion must have a behavioral replacement or a documented removal of the unsupported policy. Unrelated package tests must continue passing.

## Delivery and validation

1. Separate the default navigation wrapper from rendering and add `navigationBuilder`.
2. Unify touch recognition, contact rebasing, and bounded sample coordination.
3. Migrate policy tests and add wrapper, child-cooperation, and transition tests.
4. Update the README and example with default, disabled, and custom navigation.
5. Run focused Chrome checks during implementation; finish with analysis, one full Chrome test run, and an example web build.

```sh
flutter test --platform chrome test/navigation_test.dart test/touch_navigation_test.dart test/touch_lifecycle_test.dart test/canvas_view_test.dart
flutter analyze
flutter test --platform chrome
cd example
flutter build web
```

Real-device pinch translation remains a separate manual acceptance check. Record it as unverified if no physical touch device is available. Do not change Elseplane or publish a release as part of this refactor.

## Validation result

Implementation completed on 2026-10-29. The full Chrome suite passed all 176 tests with no skips, `flutter analyze --no-pub` reported no issues, and the example's `flutter build web` succeeded. Physical touch-device validation remains unverified.
