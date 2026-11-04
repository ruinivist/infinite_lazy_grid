# Bounds-aware culling results

## Validation

`flutter test` passed all 105 tests, and `flutter analyze` completed with no findings. Independent review identified a partial-update bug when computed bounds overflowed; the fix and four regression tests passed focused follow-up review. These checks cover correctness, not cross-platform performance.

## Linux profile measurements

The profile runs used Flutter 3.47.6 and Dart 3.13.5 on Linux x86_64. Workloads had 1,000, 10,000, or 50,000 children placed 200 logical units apart. Most children were 80 by 60; every tenth was 300 by 120, and every tenth was rotated by pi/4. Sizes were supplied. The runs covered 360 by 720 and 1440 by 900 logical-pixel viewports at scales 0.5, 1, and 2, over five deterministic pan positions. Each scenario had three warmups and five timed runs of 1,000 queries; timings are medians.

Controller query timing measured `widgetsWithScreenPositions()`, including result mapping and order work as well as index lookup. On the final implementation, query medians ranged from 20.3% lower to 5.0% higher than baseline with `minHorizontalBuildPadding: 0`. The first default-padding run ranged from 16.9% lower to 21.7% higher. Its two scenarios above the plan's 10% investigation threshold were repeated; neither reproduced above that threshold. The repeat ranged from 18.0% lower to 9.0% higher. These variable measurements do not establish a general query speedup or unchanged performance. At all 90 path positions per mode, controller result counts and sorted child-set hashes matched the raw AABB queries. The old origin-only index returned 10,735 child results; the bounds-aware index returned 11,485 with no floor and 11,586 with the default floor. These are query result counts, not mounted-child counts.

At 50,000 children, index references increased from 50,000 origin references to 100,000 AABB cell references. Reference counts do not measure memory bytes. With the 200-pixel default, final-run median controller construction times were 43.113 ms and 42.321 ms, versus 32.086 ms at baseline. Moving all 50,000 children took 63.208 ms and 61.279 ms, versus 43.696 ms at baseline.

## Limits

Only Linux desktop profile runs were measured. The runs did not measure mounted-child counts, memory, frames, or paint cost. Chrome/web, mobile, and other supported runtimes were not profiled. The widget tests verify culling and mounting behavior, but do not provide performance measurements for those paths.
