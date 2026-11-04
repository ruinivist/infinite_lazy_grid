import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_lazy_grid/core/spatial_hashing.dart';

void main() {
  group('SpatialHashing', () {
    late SpatialHashing<String> spatialHashing;

    setUp(() {
      spatialHashing = SpatialHashing<String>(cellSize: const Size(10, 10));
    });

    test('adds and retrieves a point rectangle with a zero-area query', () {
      spatialHashing.set('A', Rect.fromLTWH(5, 5, 0, 0));

      expect(spatialHashing.query(Rect.fromLTWH(5, 5, 0, 0)), ['A']);
    });

    test('keeps negative and zero-coordinate bounds', () {
      spatialHashing.set('negative', Rect.fromLTWH(-10, -10, 10, 10));
      spatialHashing.set('origin', Rect.fromLTWH(0, 0, 0, 0));

      expect(spatialHashing.query(Rect.fromLTWH(0, 0, 0, 0)).toSet(), {
        'negative',
        'origin',
      });
      expect(spatialHashing.query(Rect.fromLTWH(-10, -10, 0, 0)), ['negative']);
    });

    test('removes a child by ID', () {
      spatialHashing.set('A', Rect.fromLTWH(5, 5, 0, 0));
      spatialHashing.remove('A');

      expect(spatialHashing.query(Rect.fromLTWH(5, 5, 0, 0)), isEmpty);
    });

    test('returns multiple bounds in the same cell', () {
      spatialHashing.set('A', Rect.fromLTWH(2, 2, 2, 2));
      spatialHashing.set('B', Rect.fromLTWH(7, 7, 2, 2));

      expect(spatialHashing.query(Rect.fromLTWH(0, 0, 10, 10)).toSet(), {
        'A',
        'B',
      });
    });

    test('filters bounds outside a partial-cell query', () {
      spatialHashing.set('inside', Rect.fromLTWH(34, 34, 2, 2));
      spatialHashing.set('outside', Rect.fromLTWH(20, 20, 4, 4));

      expect(spatialHashing.query(Rect.fromLTWH(25, 25, 10, 10)), ['inside']);
    });

    test('keeps distinct IDs at the same bounds', () {
      final bounds = Rect.fromLTWH(2, 2, 5, 5);
      spatialHashing.set('A', bounds);
      spatialHashing.set('B', bounds);

      expect(spatialHashing.query(bounds).toSet(), {'A', 'B'});
    });

    test('queries bounds across multiple cells', () {
      spatialHashing.set('A', Rect.fromLTWH(5, 5, 0, 0));
      spatialHashing.set('B', Rect.fromLTWH(15, 15, 0, 0));

      expect(spatialHashing.query(Rect.fromLTWH(0, 0, 25, 25)).toSet(), {
        'A',
        'B',
      });
    });

    test('includes bounds that touch at cell boundaries', () {
      spatialHashing.set('left', Rect.fromLTRB(0, 2, 10, 8));
      spatialHashing.set('right', Rect.fromLTWH(10, 4, 2, 2));

      expect(spatialHashing.query(Rect.fromLTWH(10, 4, 0, 0)).toSet(), {
        'left',
        'right',
      });
    });

    test('deduplicates an ID indexed in multiple cells', () {
      spatialHashing.set('wide', Rect.fromLTWH(-5, -5, 30, 30));

      expect(spatialHashing.query(Rect.fromLTWH(-10, -10, 40, 40)), ['wide']);
    });

    test('replacement removes the old bounds and avoids duplicates', () {
      spatialHashing.set('A', Rect.fromLTWH(1, 1, 2, 2));
      spatialHashing.set('A', Rect.fromLTWH(25, 25, 2, 2));
      spatialHashing.set('A', Rect.fromLTWH(25, 25, 2, 2));

      expect(spatialHashing.query(Rect.fromLTWH(0, 0, 5, 5)), isEmpty);
      expect(spatialHashing.query(Rect.fromLTWH(20, 20, 10, 10)), ['A']);
    });

    test('removing one ID preserves other IDs in shared cells', () {
      spatialHashing.set('A', Rect.fromLTWH(2, 2, 2, 2));
      spatialHashing.set('B', Rect.fromLTWH(7, 7, 2, 2));
      spatialHashing.remove('A');

      expect(spatialHashing.query(Rect.fromLTWH(0, 0, 10, 10)), ['B']);
    });

    test('empty bounds are indexed at their top-left origin', () {
      spatialHashing.set('empty', Rect.fromLTWH(15, 15, 0, 8));

      expect(spatialHashing.query(Rect.fromLTWH(15, 15, 0, 0)), ['empty']);
      expect(spatialHashing.query(Rect.fromLTWH(15, 20, 0, 0)), isEmpty);
    });

    test('clear removes all entries and stale references', () {
      spatialHashing.set('A', Rect.fromLTWH(1, 1, 20, 20));
      spatialHashing.clear();
      spatialHashing.set('B', Rect.fromLTWH(1, 1, 0, 0));

      expect(spatialHashing.query(Rect.fromLTWH(0, 0, 30, 30)), ['B']);
    });

    test('rejects invalid bounds for insertion and query', () {
      expect(
        () => spatialHashing.set(
          'infinite',
          Rect.fromLTWH(double.infinity, 0, 1, 1),
        ),
        throwsArgumentError,
      );
      expect(
        () => spatialHashing.set('nan', Rect.fromLTWH(double.nan, 0, 1, 1)),
        throwsArgumentError,
      );
      expect(
        () => spatialHashing.set('unordered', Rect.fromLTRB(5, 0, 4, 1)),
        throwsArgumentError,
      );
      expect(
        () => spatialHashing.set('unorderedY', Rect.fromLTRB(0, 5, 1, 4)),
        throwsArgumentError,
      );
      expect(
        () => spatialHashing.query(Rect.fromLTRB(5, 0, 4, 1)),
        throwsArgumentError,
      );
    });

    test('rejects nonfinite or nonpositive cell sizes', () {
      for (final size in [
        const Size(0, 1),
        const Size(-1, 1),
        Size(double.infinity, 1),
        Size(double.nan, 1),
        const Size(1, 0),
        const Size(1, -1),
        Size(1, double.infinity),
        Size(1, double.nan),
      ]) {
        expect(
          () => SpatialHashing<String>(cellSize: size),
          throwsArgumentError,
        );
      }
    });

    test('fixed-region results stay stable with many far-away children', () {
      spatialHashing.set('near', Rect.fromLTWH(1, 1, 2, 2));
      final before = spatialHashing.query(Rect.fromLTWH(0, 0, 10, 10));
      for (var i = 0; i < 1000; i++) {
        spatialHashing.set(
          'far-$i',
          Rect.fromLTWH(10000 + i * 1000, 10000, 2, 2),
        );
      }

      expect(before, ['near']);
      expect(spatialHashing.query(Rect.fromLTWH(0, 0, 10, 10)), before);
    });
  });
}
