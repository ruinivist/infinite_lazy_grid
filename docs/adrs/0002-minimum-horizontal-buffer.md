# 0002: Minimum horizontal buffer

- Status: Implemented and reviewed
- Date: 2026-11-04

## Context

`buildExtentMultiplier` defaults to `2`. Before the horizontal minimum, the
build extent was the viewport size multiplied by this value and divided by the
current scale, giving half a viewport of padding on every side.

## Decision

Add the public final constructor parameter
`minHorizontalBuildPadding`, a `double` defaulting to `200` logical screen
pixels per side. Validate it at runtime: values must be finite and nonnegative,
otherwise construction throws `ArgumentError`. There is no upper limit.

Set horizontal padding on each side in screen logical pixels to
`max(viewportWidth * (buildExtentMultiplier - 1) / 2,
minHorizontalBuildPadding)`. Keep vertical padding at
`viewportHeight * (buildExtentMultiplier - 1) / 2`. The total horizontal extent
is `viewportWidth + 2 * horizontalPadding`; the total vertical extent is
`viewportHeight * buildExtentMultiplier`. Divide the complete extent by the
current scale. Add no other zoom-dependent growth.

The existing multiplier default and semantics remain, except that the
horizontal minimum is a floor even when `buildExtentMultiplier` is `1`. Passing
`minHorizontalBuildPadding: 0` restores multiplier-only extent behavior, for
example in tests that intentionally depend on the exact old extent. Do not set
zero indiscriminately in tests. This buffer is not proportional to child size:
cull known-size children only when their layout bounds are entirely outside the
buffered viewport. Bounds cover layout, not arbitrary paint overflow.

## Consequences

The 200-pixel default is a starting policy, not a measured optimum. At the
default multiplier of `2`, the existing horizontal padding is retained when it
is at least 200 pixels; narrower viewports use the minimum. Vertical padding is
unchanged. The larger horizontal region may keep more children mounted.
