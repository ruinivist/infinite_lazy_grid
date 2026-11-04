# 0001: Bounds-aware spatial hashing

- Status: Implemented and reviewed
- Date: 2026-11-04

## Context

Origin-only indexing could miss a known-size child when its origin was outside
the build region.

## Decision

Index each known-size child's rotated conservative axis-aligned layout bounds
in every overlapping spatial-hash cell. Deduplicate candidates and check their
bounds against the buffered viewport. Panning and zooming must query the index,
not scan every child; update index entries only when geometry changes. Unmount a
child when its bounds are completely outside the region. Bounds describe layout
only, not arbitrary shadow or paint overflow.

## Consequences

This uses more index references, adds geometry-update work, and can increase
mounted-child counts. No unchanged-performance claim is made. The target is
many ordinary-sized children across the library's supported platforms, without
optimizing for one device or screen shape.

Extremely large children spanning many hash cells are outside this change's
performance target. A special indexing strategy and performance guarantees for
those children are deferred until a concrete workload requires them. This does
not introduce a child-size limit or reject large children.
