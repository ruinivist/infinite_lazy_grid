import 'dart:collection';
import 'dart:math';

import 'package:flutter/material.dart';

typedef _CellKey = Point<int>;

class PointData<T> {
  final Point point;
  final T data;

  PointData(this.point, this.data);
}

/// Data structure for spatial hashing to get widgets to be built quickly
/// based on their position in a 2D grid.
class SpatialHashing<T> {
  final Size cellSize;
  final HashMap<Point, T> _pointData = HashMap<Point, T>();
  final HashMap<_CellKey, List<Point>> _cellMap = HashMap<_CellKey, List<Point>>();

  SpatialHashing({required this.cellSize});

  _CellKey _cellKey(Point point) {
    int x = (point.x / cellSize.width).floor();
    int y = (point.y / cellSize.height).floor();
    return Point(x, y);
  }

  void add(Point point, T data) {
    _CellKey cellKey = _cellKey(point);
    _pointData[point] = data;

    if (!_cellMap.containsKey(cellKey)) {
      _cellMap[cellKey] = [];
    }
    _cellMap[cellKey]!.add(point);
  }

  void remove(Point point) {
    final key = _cellKey(point);
    if (_pointData.containsKey(point)) {
      _pointData.remove(point); // remove the data

      // cell map must have key then
      _cellMap[key]!.remove(point); // remove from spatial hash
      if (_cellMap[key]!.isEmpty) {
        _cellMap.remove(key);
      }
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
        if (_cellMap.containsKey(currentCellKey)) {
          for (Point p in _cellMap[currentCellKey]!) {
            results.add(PointData(p, _pointData[p] as T));
          }
        }
      }
    }

    return results;
  }

  void clear() {
    _pointData.clear();
    _cellMap.clear();
  }
}
