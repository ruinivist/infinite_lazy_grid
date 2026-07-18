import 'dart:math';

import 'package:flutter/material.dart';

typedef _CellKey = Point<int>;

typedef PointData<T> = ({Point point, T data});

/// Data structure for spatial hashing to get widgets to be built quickly
/// based on their position in a 2D grid.
class SpatialHashing<T> {
  final Size cellSize;
  final Map<_CellKey, Map<Point, T>> _cellMap = {};

  SpatialHashing({required this.cellSize});

  _CellKey _cellKey(Point point) {
    int x = (point.x / cellSize.width).floor();
    int y = (point.y / cellSize.height).floor();
    return Point(x, y);
  }

  void add(Point point, T data) {
    final points = _cellMap.putIfAbsent(_cellKey(point), () => {});
    if (points.containsKey(point)) {
      throw ArgumentError.value(point, 'point', 'must be unique');
    }
    points[point] = data;
  }

  void remove(Point point) {
    final key = _cellKey(point);
    final points = _cellMap[key];
    points?.remove(point);
    if (points?.isEmpty ?? false) {
      _cellMap.remove(key);
    }
  }

  List<PointData<T>> getPointsAround(Point point, Offset offset) {
    _CellKey cellKey = _cellKey(point);
    List<PointData<T>> results = [];

    // Calculate the range of cells to check
    int startX = cellKey.x - (offset.dx / cellSize.width).floor();
    int startY = cellKey.y - (offset.dy / cellSize.height).floor();
    int endX = cellKey.x + (offset.dx / cellSize.width).ceil();
    int endY = cellKey.y + (offset.dy / cellSize.height).ceil();

    for (int x = startX; x <= endX; x++) {
      for (int y = startY; y <= endY; y++) {
        Point currentCellKey = Point(x, y);
        final points = _cellMap[currentCellKey];
        if (points != null) {
          for (final entry in points.entries) {
            results.add((point: entry.key, data: entry.value));
          }
        }
      }
    }

    return results;
  }

  void clear() {
    _cellMap.clear();
  }
}
