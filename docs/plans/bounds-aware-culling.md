# Bounds-aware culling plan

Implementation and independent review are complete for the accepted decisions in `docs/adrs/0001-bounds-aware-spatial-hashing.md`, `docs/adrs/0002-minimum-horizontal-buffer.md`, and `docs/adrs/0003-size-dependent-culling.md`. This plan records the scope, contract, and execution checks.

## 1. Baseline inspection and scope (completed)

The baseline review checked repository status, the ADRs and this plan, then traced callers, child mutations, cached sizes, culling queries, and invalidation. Relevant code is in `lib/core/spatial_hashing.dart`, `lib/core/controller/controller.dart`, `lib/core/controller/types.dart`, and `lib/core/render.dart`. Relevant tests include `test/core/spatial_hashing_test.dart`, `test/child_rotation_test.dart`, `test/child_updates_test.dart`, `test/child_overlap_test.dart`, `test/child_order_test.dart`, `test/child_focus_test.dart`, and `test/canvas_view_test.dart`. `lib/infinite_lazy_grid.dart` already exports the controller. Unrelated analyzer configuration and public behavior outside the accepted decisions were left unchanged.

The target is many ordinary-sized children across every platform supported by the library, not one screen shape or device. Very large children spanning many hash cells are not an optimization target; the implementation does not reject them or add a size limit. Unknown-size first appearance remains path-dependent as accepted in ADR 0003. The workload and product decisions were resolved before implementation. Unsupported measurements are listed as evidence gaps rather than covered by a compatibility layer, platform setup, dependency, benchmark framework, or workaround.

## 2. Baseline and profile comparison (completed)

The baseline and candidate runs used 1,000, 10,000, and 50,000 children on a reproducible grid with 200 logical units between origins. Most children measured 80 by 60, about 10 percent measured 300 by 120, and about 10 percent used a pi/4 rotation. The runs covered 360 by 720 and 1440 by 900 logical-pixel viewports at scales 0.5, 1, and 2, along the same five pan positions. Temporary local checks used profile mode, with three warmups and five timed repetitions; results report medians. No benchmark tooling was added.

The integrated version was compared at `minHorizontalBuildPadding: 0` and at the 200-pixel default. Linux profile measurements and their limits are recorded in [the results](bounds-aware-culling-results.md). They cover controller query results and index work, not mounted-child counts, frames, paint cost, or memory. Source review confirms sparse queries use the spatial index and sort only returned candidates; query time still depends on candidate count. Performance on other supported runtimes remains unverified.

## 3. Rectangle index and integration (implemented)

The internal index supports rectangle set, remove, query, and clear operations keyed by child ID. It stores each known child's conservative rotated layout AABB in every overlapping cell, deduplicates IDs returned from multi-cell queries, and checks candidate bounds against the query. False-positive candidates are acceptable; culling does not require exact polygon tests. Unknown and empty-size children retain origin bounds. The internal API changes with its callers and tests; no compatibility layer preserves the old point-only signature.

Index tests cover negative coordinates, finite geometry, zero and empty sizes, boundaries, rotated AABBs, multi-cell insertion, removal and replacement, duplicate-free queries, shared-cell removal, and clear without stale references. Empty-size children remain eligible by origin.

The controller indexes supplied sizes and actual layout measurements. Position, size, and rotation changes refresh that child's index entry, including updates while culled; removal and clear remove stale references. Actual layout refreshes a supplied size when constraints produce a different size. Measurement invalidation is coalesced after layout. Culling does not eagerly or offstage-measure children. Unknown-size discovery remains origin-based until normal layout measures the child. Pan and zoom query the index and sort only returned candidates by paint order.

## 4. Behavior checks and closeout (completed)

Tests cover known-size and rotated bounds, unknown-size origin fallback and its path-dependent first appearance, matching supplied sizes, viewport resize and zoom, measured-size refresh, offscreen geometry changes, removal, clear, and render callbacks. Existing tests cover clipping, hit testing, paint order, focus, overlap queries, and vertical padding. Buffer tests cover invalid values, zero, multiplier 1, scale conversion, and the 200-pixel default. Spatial tests cover finite geometry, negative coordinates, and boundaries. Culling uses rotated AABBs, not exact rotated-polygon tests.

The implementation passed `flutter test` with 105 tests and `flutter analyze` with no findings. The README, unreleased changelog, and ADR statuses reflect the implementation. The constructor parameter `minHorizontalBuildPadding` is a final `double`, defaults to 200 logical screen pixels per side, and rejects nonfinite or negative values with `ArgumentError`. The existing `lib/infinite_lazy_grid.dart` export remains unchanged. Horizontal per-side padding is `max(viewportWidth * (buildExtentMultiplier - 1) / 2, minHorizontalBuildPadding)`; vertical padding remains `viewportHeight * (buildExtentMultiplier - 1) / 2`. The complete build extent is divided by scale. Existing multiplier behavior remains except for the horizontal floor, including at multiplier 1. Tests that intentionally assert the old exact extent can set `minHorizontalBuildPadding: 0`.

Independent review found a computed-bounds overflow that could leave failed geometry changes partially applied. The correction validates bounds before mutation, including batch operations, and adds four regression tests. A focused follow-up review found no remaining issues with that correction. Linux profile comparisons were repeated after the correction. Do not treat these results as cross-platform performance evidence.
