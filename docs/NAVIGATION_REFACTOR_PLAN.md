# Navigation refactor plan

## Goal and scope

Give `LazyCanvas` useful navigation defaults and let applications override gesture decisions without rebuilding pan, pinch, or inertia. Keep viewport rendering independent of input policy. Breaking public API changes are allowed. Application migration, including Elseplane, is separate work.

The outstanding bug is jittery translation during two-finger zoom. Fix it in shared navigation handling rather than adding another implementation selected by a touch mode.

## Starting point

The implementation and README are restored to `f6053f7`, before the two touch stabilization commits. All tests from `6fbda1c` and `70e0d7c` remain unchanged, including the updated `canvas_view_test.dart` and the three added touch test files. Git history is preserved.

The retained tests describe both general navigation guarantees and particular interaction policies. Some intentionally fail against this baseline. Do not skip them or weaken their assertions to make the rollback green.

Chrome validation on 2026-10-29 produced these results using the command below:

| Test file | Before rollback | After rollback |
| --- | --- | --- |
| `touch_navigation_test.dart` | 69 passed | 37 passed, 32 failed |
| `touch_lifecycle_test.dart` | 24 passed | 10 passed, 14 failed |
| `canvas_view_test.dart` | 31 passed | 31 passed |
| Total | 124 passed | 78 passed, 46 failed |

Analysis reported no issues after the rollback. The failures include motion timing, stationary anchoring, coincident contacts, and fixed-pair lifetime behavior; they are not all evidence of the same translation bug.

Current navigation has two paths in `lib/core/render.dart`: a Flutter scale recognizer for `oneFinger`, and raw touch tracking for `twoFinger`. Both call the controller's scale methods, but they calculate touch movement and manage their lifetimes differently. Wheel and pointer-scale input use additional handlers in the same render widget.

## Ownership

| Component | Owns |
| --- | --- |
| `LazyCanvas` | Viewport composition, lazy rendering, child layout, painting, and hit testing |
| Navigation handling | Contact tracking, recognition, sample coordination, and gesture lifetime |
| `LazyCanvasController` | Applying viewport transforms, coordinate conversion, zoom limits, animation, and inertia |
| Application | Deciding whether input navigates or performs an application action; coordinating its own interrupted operations |

Different devices can have different input adapters. They must use the same viewport transform operations. All touch navigation must share contact geometry and sample coordination, regardless of how many contacts were required to start it.

## Public behavior and overrides

Start with a small API rather than a general gesture framework:

- Default to one-finger panning, pinch zoom, mouse dragging, wheel scrolling, and trackpad navigation. Respect child gesture recognition and nested scrolling.
- Provide an admission callback with the device kind, buttons, contact count, canvas-local position, and relevant modifier state. Evaluate admission when navigation could start and when contacts change. Continue tracking candidate contacts after rejection so a second finger can qualify later. Once admitted, maintain a defined lifetime rather than repeatedly toggling navigation on every move.
- Report navigation start, update, end, and cancellation consistently. Distinguish a normal release from cancellation, and identify participating pointers when application coordination needs them.
- Keep wheel replacement behavior available. Treat pan and scale as one transform update so separate handlers cannot apply inconsistent anchors or duplicate movement.
- Provide a focal-point override for the stationary-finger behavior already covered by tests. Supply previous and current received contact positions in local coordinates; keep sample coordination private and apply the chosen anchor through the shared transform operation.
- Let consumers disable built-in navigation and use their own Flutter input handling against the same controller operations. This is the escape hatch for custom recognition; do not add a callback for every internal sampling decision.

Remove `TouchNavigationMode` once its consumers are covered by these controls. Do not retain separate one-finger and two-finger engines behind renamed options.

A two-contact admission rule does not imply taking over an existing child drag. Raw observation does not cancel child recognizers or stop pointer delivery. Any forced takeover must be an explicit integration contract that requires application cooperation, with documented callback ordering. It must not be a side effect of the contact count.

Normal navigation should transition between one and two contacts without a viewport jump. Freezing until every contact releases, retaining only the original pair, and disabling inertia for every two-contact gesture are optional policies rather than universal behavior. Preserve tests for these policies in explicit fixtures when supported. Keep their implementation out of the rendering code.

## Shared motion handling

The removed frame coordination addressed incomplete contact samples: one finger's update can arrive before the other's, briefly making a pan resemble a pinch. This is separate from easing or inertia.

Use one internal touch calculation path. A single participating contact produces translation. Two participating contacts produce translation and scale together. Changing the contact set establishes a new baseline without changing the current viewport. Define how additional contacts participate without allowing them to cause a discontinuity.

Keep sample coordination private and bounded. Equivalent received input must receive equivalent treatment; the implementation cannot know whether an absent partner update will arrive. If waiting for a partner is necessary, retain the existing maximum of one additional display frame. New input must not renew an older sample's deadline. Do not add pan-versus-pinch locking, a movement dead zone after recognition, or animation that continues toward stale targets while fingers are still down.

Apply zoom limits and panning together. Coincident contacts must remain finite and preserve usable scale references. Cancel pending work on disposal or controller replacement so no late transform reaches a detached controller. Normal release must account for final received movement; cancellation must not start inertia.

Use centroid anchoring as the default geometry. Stationary-finger anchoring, especially during diagonal movement, is a distinct behavior choice. Retain its tests under an explicit anchoring override rather than silently imposing it on all consumers. The override must reuse shared tracking and transforms.

## Implementation sequence

1. **Record the baseline.** Run the retained touch suites and record failures by behavior. Keep the tests byte-for-byte unchanged during the rollback. Capture a short manual reproduction of jittery pinch translation before changing navigation.
2. **Separate input from rendering.** Move navigation code out of `render.dart` into one focused implementation file. Reuse the controller's existing transform and inertia machinery. Avoid adding a second controller or exporting internal helpers.
3. **Unify touch calculations.** Route one-contact and multi-contact movement through shared tracking, baseline transitions, sample coordination, and combined transform updates. Resolve coordinate-space and anchoring errors at this boundary. Preserve different device adapters where needed.
4. **Add admission and lifecycle overrides.** Cover default navigation, rejected single-contact navigation followed by admitted two-contact navigation, and custom input with built-in navigation disabled. Replace the mode-specific API and document cancellation and child interaction.
5. **Separate policy tests.** Keep general motion acceptance tests on the defaults and on the two-contact admission override. Move policy-specific expectations into explicitly configured fixtures. Preserve their behavioral assertions and independent rendered-motion checks. Update tests only as required by the new API or an explicitly documented default change.
6. **Update the example and documentation.** Show the defaults, a two-contact admission override, and custom navigation driving the existing controller. Remove instructions that require every consumer to guard its input because of an implicit takeover mode.

Complete the steps in order, with the refactor and motion fix reviewed as distinct changes where practical. The rollback itself leaves the original issue open.

## Test coverage to retain

| Coverage | Placement after refactor |
| --- | --- |
| Pan without temporary zoom pulses; pinch with stable translation | Shared touch behavior, including navigation that starts with one contact |
| Independent input/display timing at 60 and 120 Hz; response deadlines | Shared multi-contact sampling |
| Zoom limits, subpixel movement, coincident contacts, and rotation without zoom | Shared transform behavior |
| Stationary-finger anchoring and anchor transitions | Explicit anchoring behavior |
| Fixed original pair, ignored extra contacts, and drain-until-release | Explicit contact-lifetime behavior |
| Ownership before raw delivery and takeover after a child wins | Explicit takeover integration |
| Release/cancel, controller replacement, disposal, and late callbacks | Shared lifecycle plus relevant policy fixtures |
| Mouse buttons, trackpad, wheel replacement, and nested scrolling | Device adapters and child cooperation |

Keep the independent geometry oracle, rendered landmark checks, and negative controls that prove transient errors are detected. Correct endpoints alone do not establish smooth motion. Add focused tests for one-to-two-to-one contact transitions and for callback ordering when navigation is rejected, starts, ends, or is canceled.

## Validation and completion

Use Chrome for interaction tests:

```sh
flutter test --platform chrome test/touch_navigation_test.dart test/touch_lifecycle_test.dart test/canvas_view_test.dart
flutter analyze
```

During implementation, run the relevant files. Before committing the completed feature or fix, run the full package suite once in Chrome and build the example for web. Verify pinch translation manually with real touch input; browser replay is a regression check, not a substitute for device validation.

Completion means shared touch motion is stable under the retained frame-by-frame checks, default and overridden navigation reuse the same calculations, and application-specific contact policies no longer determine the library's internal engine. The current rollback is deliberately short of that state.
