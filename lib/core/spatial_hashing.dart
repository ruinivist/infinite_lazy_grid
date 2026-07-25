import 'dart:math';

import 'package:flutter/material.dart';

typedef _CellKey = Point<int>;

typedef PointData<T> = ({Point point, T data});

/// Data structure for spatial hashing to get widgets to be built quickly
/// based on their position in a 2D grid.
class SpatialHashing<T> {
  final Size cellSize;
  final Map<_CellKey, List<PointData<T>>> _cellMap = {};

  SpatialHashing({required this.cellSize});

  _CellKey _cellKey(Point point) {
    int x = (point.x / cellSize.width).floor();
    int y = (point.y / cellSize.height).floor();
    return Point(x, y);
  }

  void add(Point point, T data) {
    _cellMap.putIfAbsent(_cellKey(point), () => []).add((
      point: point,
      data: data,
    ));
  }

  void remove(Point point, T data) {
    final key = _cellKey(point);
    final points = _cellMap[key];
    points?.removeWhere((item) => item.point == point && item.data == data);
    if (points?.isEmpty ?? false) {
      _cellMap.remove(key);
    }
  }

  List<PointData<T>> getPointsAround(Point point, Offset offset) {
    final left = point.x - offset.dx;
    final right = point.x + offset.dx;
    final top = point.y - offset.dy;
    final bottom = point.y + offset.dy;
    final start = _cellKey(Point(left, top));
    final end = _cellKey(Point(right, bottom));
    final results = <PointData<T>>[];

    for (int x = start.x; x <= end.x; x++) {
      for (int y = start.y; y <= end.y; y++) {
        final points = _cellMap[Point(x, y)];
        if (points != null) {
          for (final item in points) {
            final candidate = item.point;
            if (candidate.x >= left &&
                candidate.x <= right &&
                candidate.y >= top &&
                candidate.y <= bottom) {
              results.add(item);
            }
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
