import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_lazy_grid/core/spatial_hashing.dart';
import 'dart:math';
import 'package:flutter/material.dart';

void main() {
  group('SpatialHashing', () {
    late SpatialHashing<String> spatialHashing;

    setUp(() {
      spatialHashing = SpatialHashing<String>(cellSize: const Size(10, 10));
    });

    test('add and retrieve single point', () {
      final point = Point(5, 5);
      spatialHashing.add(point, 'A');
      final results = spatialHashing.getPointsAround(point, const Offset(0, 0));
      expect(results.length, 1);
      expect(results.first, (point, 'A'));
    });

    test('remove point', () {
      final point = Point(5, 5);
      spatialHashing.add(point, 'A');
      spatialHashing.remove(point);
      final results = spatialHashing.getPointsAround(point, const Offset(0, 0));
      expect(results, isEmpty);
    });

    test('add multiple points in same cell', () {
      final p1 = Point(2, 2);
      final p2 = Point(7, 7);
      spatialHashing.add(p1, 'A');
      spatialHashing.add(p2, 'B');
      final results = spatialHashing.getPointsAround(p1, const Offset(0, 0));
      expect(results.length, 2);
      expect(results, contains((p1, 'A')));
      expect(results, contains((p2, 'B')));
    });

    test('add points in different cells and query with offset', () {
      final p1 = Point(5, 5);
      final p2 = Point(15, 15);
      spatialHashing.add(p1, 'A');
      spatialHashing.add(p2, 'B');
      // Query with offset to include both cells
      final results = spatialHashing.getPointsAround(p1, const Offset(10, 10));
      expect(results.length, 2);
      expect(results, contains((p1, 'A')));
      expect(results, contains((p2, 'B')));
    });

    test('removing one of multiple points in a cell', () {
      final p1 = Point(2, 2);
      final p2 = Point(7, 7);
      spatialHashing.add(p1, 'A');
      spatialHashing.add(p2, 'B');
      spatialHashing.remove(p1);
      final results = spatialHashing.getPointsAround(p2, const Offset(0, 0));
      expect(results.length, 1);
      expect(results.first, (p2, 'B'));
    });
  });
}
