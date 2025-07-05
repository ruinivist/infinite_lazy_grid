import 'package:flutter/material.dart';
import 'package:infinite_lazy_2d_grid/core/spatial_hashing.dart';
import 'package:infinite_lazy_2d_grid/utils/offset_extensions.dart';
import '../../utils/conversions.dart';
import '../../utils/styles.dart';

part 'debug.dart';
part 'types.dart';

/// Every canvas view needs one and this handles the positioning logic
class CanvasController with ChangeNotifier {
  int _nextId = 0; // surely we won't run out of IDs, Clueless
  Offset _gsTopLeftOffset = Offset.zero;
  double _baseScale, _scale;
  late Size _canvasSize;
  final Map<int, _ChildInfo> _children = {}; // int for IDs
  final Offset? _buildCacheExtent;
  late Offset _buildExtent;
  final Size _hashCellSize;
  bool _init = false;
  late final SpatialHashing<int> _spatialHash;

  bool debug;

  CanvasController({
    double initialScale = 1,
    this.debug = false,
    Offset? buildCacheExtent,
    Size hashCellSize = const Size(100, 100),
  }) : _scale = initialScale,
       _baseScale = initialScale,
       _hashCellSize = hashCellSize,
       _buildCacheExtent = buildCacheExtent != null ? buildCacheExtent + Offset(50, 50) : null,
       // only top left is considered to if a widget has long width, it'll not be rendered
       // unless the cache extent is sufficient
       assert(initialScale > 0, 'Initial scale must be greater than 0') {
    _spatialHash = SpatialHashing<int>(cellSize: _hashCellSize);
  }

  // ==================== Getters ====================
  Offset get offset => _gsTopLeftOffset;
  double get scale => _scale;
  Size get canvasSize => _canvasSize;
  Offset get _ssCenter => Offset(_canvasSize.width / 2, _canvasSize.height / 2);
  Offset get _gsCenter => ssToGs(_ssCenter, _gsTopLeftOffset, _scale);

  // ==================== Public Functions ====================

  /// Update the canvas size when the widget size changes.
  void onCanvasSizeChange(Size size) {
    if (size == Size.zero) return; // ignore the zero side, linux first build pass error
    if (_init && size == _canvasSize) return;

    _buildExtent = Offset(size.width, size.height) + (_buildCacheExtent ?? Offset(size.width * 0.1, size.height * 0.1));
    _canvasSize = size; // allow resize due to canvas resize

    // if the first init, re-render as not I have the canvas size to build widgets
    if (!_init) {
      _init = true;
      Future.microtask(notifyListeners);
    }
  }

  // ==================== Child Management ====================

  /// Add a child at a given position with a builder. Returns the child ID.
  int addChild(Offset position, WidgetBuilder builder) {
    _children[_nextId] = _ChildInfo(gsPosition: position, builder: builder);
    _spatialHash.add(position.toPoint(), _nextId); // add to spatial hash
    return _nextId++;
  }

  /// Remove a child by its ID.
  void removeChild(int id) {
    if (!_children.containsKey(id)) {
      throw _ChildNotFoundException;
    }
    _spatialHash.remove(_children[id]!.gsPosition.toPoint());
    _children.remove(id);
  }

  /// Update the position of a child by its ID.
  int updatePosition(int id, Offset newPosition) {
    if (_children.containsKey(id)) {
      _children[id]!.gsPosition = newPosition;
      return id;
    } else {
      throw _ChildNotFoundException;
    }
  }

  /// Get the position of a child by its ID.
  Offset getPosition(int id) {
    if (_children.containsKey(id)) {
      return _children[id]!.gsPosition;
    } else {
      throw _ChildNotFoundException;
    }
  }

  // ==================== Gesture Handling ====================

  /// Called when a scale gesture starts.
  void onScaleStart(ScaleStartDetails details) {
    _baseScale = _scale;
  }

  /// Called when a scale gesture updates.
  /// Usually you would not want to override this
  void onScaleUpdate(ScaleUpdateDetails details) {
    // uses usual display conventions and final vector postion - initial vector position
    // convention is that if I drag from right to left, dx is negative
    // for top to bottom, dy is postive

    // scale + offset => scale then offset

    if (details.scale != 1) {
      final newScale = _baseScale * details.scale;
      _gsTopLeftOffset = newGsTopLeftOnScaling(_gsTopLeftOffset, details.localFocalPoint, _scale, newScale);
      _scale = newScale;
    }

    if (details.focalPointDelta != Offset.zero) {
      // if ss distnace is x, and zoom is 2x, gs only moves by x/2
      _gsTopLeftOffset -= details.focalPointDelta / _scale;
    }

    notifyListeners();
  }

  /// Increment or decrement the scale by a delta value.
  void updateScalebyDelta(double delta) {
    final focalPoint = Offset(canvasSize.width / 2, canvasSize.height / 2);
    final newScale = _scale + delta;
    _gsTopLeftOffset = newGsTopLeftOnScaling(_gsTopLeftOffset, focalPoint, _scale, newScale);
    _scale = newScale;
    notifyListeners();
  }

  // ==================== Positioning Logic ====================

  /// Currently rendered widgets with their position info
  List<ChildInfo> widgetsWithScreenPositions() {
    if (!_init) return [];

    final idsToBuild = _childrenWithinBuildArea(_gsCenter, _buildExtent);
    print("building ${idsToBuild.length} widgets at ${_gsCenter.toPoint()} with extent ${_buildExtent.toPoint()}");

    return idsToBuild.map((id) {
      final item = _children[id]!;
      final ssPosition = gsToSs(item.gsPosition, _gsTopLeftOffset, _scale);
      var child = item.builder();
      if (debug) child = _Debug(id: id, gs: item.gsPosition, ss: ssPosition, child: child);
      return ChildInfo(gsPosition: item.gsPosition, ssPosition: ssPosition, child: child);
    }).toList();
  }

  List<int> _childrenWithinBuildArea(Offset center, Offset extent) {
    Offset halfExtent = Offset((extent.dx / (2 * _scale)).ceilToDouble(), (extent.dy / (2 * _scale)).ceilToDouble());
    final items = _spatialHash.getPointsAround(center.toPoint(), halfExtent);
    return items.map((item) => item.data).toList(); // data is the child id here
  }
}
