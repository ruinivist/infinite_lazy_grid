import 'dart:math';

import 'package:flutter/material.dart';

typedef _CellKey = Point<int>;

/// Data structure for spatial hashing to get widgets to be built quickly
/// based on their bounds in a 2D grid.
class SpatialHashing<T> {
  final Size cellSize;
  final Map<_CellKey, Set<T>> _cellMap = {};
  final Map<T, Rect> _boundsById = {};

  SpatialHashing({required this.cellSize}) {
    if (!cellSize.width.isFinite ||
        !cellSize.height.isFinite ||
        cellSize.width <= 0 ||
        cellSize.height <= 0) {
      throw ArgumentError.value(
        cellSize,
        'cellSize',
        'Must be finite and positive',
      );
    }
  }

  Rect _validatedBounds(Rect bounds, String name) {
    if (!bounds.left.isFinite ||
        !bounds.top.isFinite ||
        !bounds.right.isFinite ||
        !bounds.bottom.isFinite ||
        bounds.left > bounds.right ||
        bounds.top > bounds.bottom) {
      throw ArgumentError.value(bounds, name, 'Must be finite and ordered');
    }
    return bounds.isEmpty
        ? Rect.fromLTWH(bounds.left, bounds.top, 0, 0)
        : bounds;
  }

  // shortcut: huge bounds span many cells; add oversized indexing if needed.
  Iterable<_CellKey> _cells(Rect bounds) sync* {
    final startX = (bounds.left / cellSize.width).floor();
    final endX = (bounds.right / cellSize.width).floor();
    final startY = (bounds.top / cellSize.height).floor();
    final endY = (bounds.bottom / cellSize.height).floor();

    for (var x = startX; x <= endX; x++) {
      for (var y = startY; y <= endY; y++) {
        yield Point(x, y);
      }
    }
  }

  void set(T id, Rect bounds) {
    final newBounds = _validatedBounds(bounds, 'bounds');
    final oldBounds = _boundsById[id];
    if (oldBounds == newBounds) return;
    if (oldBounds != null) _removeFromCells(id, oldBounds);

    _boundsById[id] = newBounds;
    for (final key in _cells(newBounds)) {
      _cellMap.putIfAbsent(key, () => <T>{}).add(id);
    }
  }

  void _removeFromCells(T id, Rect bounds) {
    for (final key in _cells(bounds)) {
      final ids = _cellMap[key];
      ids?.remove(id);
      if (ids?.isEmpty ?? false) _cellMap.remove(key);
    }
  }

  void remove(T id) {
    final bounds = _boundsById.remove(id);
    if (bounds != null) _removeFromCells(id, bounds);
  }

  List<T> query(Rect area) {
    final queryBounds = _validatedBounds(area, 'area');
    final seen = <T>{};
    final results = <T>[];

    for (final key in _cells(queryBounds)) {
      final ids = _cellMap[key];
      if (ids == null) continue;
      for (final id in ids) {
        if (!seen.add(id)) continue;
        final bounds = _boundsById[id]!;
        if (bounds.left <= queryBounds.right &&
            bounds.right >= queryBounds.left &&
            bounds.top <= queryBounds.bottom &&
            bounds.bottom >= queryBounds.top) {
          results.add(id);
        }
      }
    }

    return results;
  }

  void clear() {
    _cellMap.clear();
    _boundsById.clear();
  }
}
