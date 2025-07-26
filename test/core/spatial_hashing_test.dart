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
      expect(results.first.point, point);
      expect(results.first.data, 'A');
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
      expect(results.any((pointData) => pointData.point == p1 && pointData.data == 'A'), isTrue);
      expect(results.any((pointData) => pointData.point == p2 && pointData.data == 'B'), isTrue);
    });

    test('add points in different cells and query with offset', () {
      final p1 = Point(5, 5);
      final p2 = Point(15, 15);
      spatialHashing.add(p1, 'A');
      spatialHashing.add(p2, 'B');
      // Query with offset to include both cells
      final results = spatialHashing.getPointsAround(p1, const Offset(10, 10));
      expect(results.length, 2);
      expect(results.any((pointData) => pointData.point == p1 && pointData.data == 'A'), isTrue);
      expect(results.any((pointData) => pointData.point == p2 && pointData.data == 'B'), isTrue);
    });

    test('removing one of multiple points in a cell', () {
      final p1 = Point(2, 2);
      final p2 = Point(7, 7);
      spatialHashing.add(p1, 'A');
      spatialHashing.add(p2, 'B');
      spatialHashing.remove(p1);
      final results = spatialHashing.getPointsAround(p2, const Offset(0, 0));
      expect(results.length, 1);
      expect(results.first.point, p2);
      expect(results.first.data, 'B');
    });
  });
}
