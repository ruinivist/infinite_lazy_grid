# 0003: Size-dependent culling

- Status: Implemented and reviewed
- Date: 2026-11-04

## Context

The controller accepts supplied sizes and records normal layout measurements.
Origin-only culling could miss a known-size child whose layout bounds entered
the build region before its origin did.

## Decision

Use supplied `childSize` or normal layout measurements for bounds-aware
culling. Keep measured sizes cached after a child is culled and refresh them
from actual layout. Callers must update geometry that changes while a child is
offscreen. Discover children with unknown or empty sizes by origin. Do not
measure offstage solely for culling. A wide child with an unknown size can be
missed on first approach until normal layout measures it; supplying a size that
matches actual layout avoids this gap. The existing explicit offstage
measurement in `focusOnChild` is unchanged.

## Consequences

Known sizes allow bounds-aware discovery without adding a separate measurement
pass. Unknown-size children retain the existing discovery limitation until
layout supplies a size.

Path-dependent first appearance is an accepted trade-off. A wide child with an
unknown size can be missed when its origin is outside the build region, even
though part of it should be visible. Panning until its origin enters the region
mounts and measures it. Returning along the same path can then show it where it
was previously missing, because the index now knows its bounds. Supplying
`childSize` avoids this initial discovery gap, provided it matches the layout.
