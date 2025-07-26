import 'dart:collection';

import 'package:flutter/material.dart';
import '../../utils/measure_size.dart';
import '../spatial_hashing.dart';
import '../../utils/offset_extensions.dart';
import '../../utils/size_extensions.dart';
import '../../utils/conversions.dart';
import '../../utils/styles.dart';
import '../render.dart';

part 'debug.dart';
part 'types.dart';

/// Controller for [LazyCanvas]
class LazyCanvasController with ChangeNotifier {
  int _nextId = 0; // surely we won't run out of IDs, Clueless
  Offset _gsTopLeftOffset = Offset.zero;
  double _baseScale = 1, _scale = 1;
  late Size _canvasSize;
  final HashMap<int, _ChildInfo> _children = HashMap<int, _ChildInfo>(); // int for IDs
  final Offset? _buildCacheExtent;
  late Offset _buildExtent;
  final Size _hashCellSize;
  bool _init = false;
  late final SpatialHashing<int> _spatialHash;
  TickerProvider? _ticker;
  late BuildContext _context;

  bool debug;
  final Duration defaultAnimationDuration;

  LazyCanvasController({
    this.debug = false,
    Offset? buildCacheExtent,
    Size hashCellSize = const Size(100, 100),
    this.defaultAnimationDuration = const Duration(milliseconds: 300),
  }) : _hashCellSize = hashCellSize,
       _buildCacheExtent = buildCacheExtent != null ? buildCacheExtent + Offset(50, 50) : null
  // only top left is considered so if a widget has long width, it'll not be rendered
  // unless the cache extent is sufficient
  {
    _spatialHash = SpatialHashing<int>(cellSize: _hashCellSize);
  }

  // ==================== Getters ====================
  Offset get offset => _gsTopLeftOffset;
  double get scale => _scale;
  Size get canvasSize => _canvasSize;
  Offset get _ssCenter => Offset(_canvasSize.width / 2, _canvasSize.height / 2);
  Offset get _gsCenter => ssToGs(_ssCenter, _gsTopLeftOffset, _scale);

  // ==================== Callback Functions ====================

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

  /// Called when a child widget's size changes.
  void onChildSizeChange(int id, Size size) {
    _children[id]!.lastRenderedSize = size;
  }

  /// Set the ticker provider for animations.
  void setTickerProvider(TickerProvider ticker) {
    _ticker = ticker;
  }

  void setBuildContext(BuildContext context) {
    _context = context;
  }

  // ==================== Child Management ====================

  /// Add a child at a given position with a widget. Returns the child ID.
  int addChild(Offset position, Widget widget) {
    _children[_nextId] = _ChildInfo(gsPosition: position, widget: widget);
    _spatialHash.add(position.toPoint(), _nextId); // add to spatial hash
    notifyListeners();
    return _nextId++;
  }

  /// Remove a child by its ID.
  void removeChild(int id) {
    if (!_children.containsKey(id)) {
      throw _ChildNotFoundException;
    }
    _spatialHash.remove(_children[id]!.gsPosition.toPoint());
    _children.remove(id);
    notifyListeners();
  }

  /// Remove all children. Does not change where you are on the canvas.
  void clear() {
    _children.clear();
    _spatialHash.clear();
    _nextId = 0;
    notifyListeners();
  }

  /// Update the position of a child by its ID.
  int updatePosition(int id, Offset newPosition) {
    if (_children.containsKey(id)) {
      _children[id]!.gsPosition = newPosition;
      notifyListeners();
      return id;
    } else {
      throw _ChildNotFoundException;
    }
  }

  /// Update a child's widget.
  void updateChildWidget(int id, Widget newWidget) {
    if (_children.containsKey(id)) {
      final child = _children[id]!;
      // Create a new _ChildInfo with the new widget
      _children[id] = _ChildInfo(gsPosition: child.gsPosition, widget: newWidget)
        ..lastRenderedSize = child.lastRenderedSize;
      notifyListeners();
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

  /// Increment or decrement the scale by an additive delta value.
  void updateScalebyDelta(double delta) {
    final focalPoint = Offset(canvasSize.width / 2, canvasSize.height / 2);
    final newScale = _scale + delta;
    _gsTopLeftOffset = newGsTopLeftOnScaling(_gsTopLeftOffset, focalPoint, _scale, newScale);
    _scale = newScale;
    notifyListeners();
  }

  // ==================== Positioning Logic ====================

  /// Currently rendered widgets with their position info
  List<ChildInfo> widgetsWithScreenPositions({bool forceRebuild = false}) {
    if (!_init) return [];

    final idsToBuild = _childrenWithinBuildArea(_gsCenter, _buildExtent);

    return idsToBuild.map((id) {
      final item = _children[id]!;
      final ssPosition = gsToSs(item.gsPosition, _gsTopLeftOffset, _scale);
      var child = item.widget;
      if (debug) child = _Debug(id: id, gs: item.gsPosition, ss: ssPosition, child: child);
      return ChildInfo(id: id, gsPosition: item.gsPosition, ssPosition: ssPosition, child: child);
    }).toList();
  }

  List<int> _childrenWithinBuildArea(Offset center, Offset extent) {
    Offset halfExtent = Offset((extent.dx / (2 * _scale)).ceilToDouble(), (extent.dy / (2 * _scale)).ceilToDouble());
    final items = _spatialHash.getPointsAround(center.toPoint(), halfExtent);
    return items.map((item) => item.data).toList(); // data is the child id here
  }

  // ==================== Centering & Focus Functions ====================

  /// Center the canvas so that the given screen-space offset is at the center of the viewport.
  void centerOnScreenOffset(Offset ssOffset, {Duration? duration, bool animate = true}) {
    centerOnGridOffset(ssToGs(ssOffset, _gsTopLeftOffset, _scale), animate: animate);
  }

  /// Center the canvas so that the given grid-space offset is at the center of the viewport.
  void centerOnGridOffset(Offset gsOffset, {Duration? duration, bool animate = true}) {
    // if 2x scale you need to adjust lesser
    final newGsTopLeft = gsOffset + (canvasSize * (2 * scale)).toOffset();
    if (animate) {
      animateToOffsetAndScale(offset: newGsTopLeft, duration: duration, scale: _scale);
    } else {
      _gsTopLeftOffset = newGsTopLeft;
      notifyListeners();
    }
  }

  /// Focus the viewport on a child by its ID, with a margin in screen-space.
  /// If it's already rendered, size will be picked up from the child widget. If not
  /// an offstage rendering will be used ( double render )
  /// Preferred horizontal margin used for [ScalingMode.fitInViewport].
  void focusOnChild(
    int id, {
    ScalingMode scalingMode = ScalingMode.keepScale,
    bool animate = true,
    double preferredHorizontalMargin = 16,
    Duration? duration,
    Size? childSize,
    forceRedraw = false,
  }) {
    if (!_children.containsKey(id)) {
      throw _ChildNotFoundException;
    }

    final childInfo = _children[id]!;

    // try to figure out the size, take from render cache if available
    // else do an offstage render
    childSize ??= childInfo.lastRenderedSize != null && !forceRedraw
        ? childInfo.lastRenderedSize
        : measureWidgetSize(_context, (_) => childInfo.widget);

    /*
    margin is symmatric on ltrb so
    2mx + cx = screenWidth
    2my + cy = screenHeight
    where c is child size in screen space and m is margin
    */

    double newScale = _scale;
    Offset newGsTopLeft = _gsTopLeftOffset;

    switch (scalingMode) {
      case ScalingMode.keepScale:
        // do nothing
        break;
      case ScalingMode.resetScale:
        newScale = 1;
      case ScalingMode.fitInViewport:
        // the scale needs to be determined in this case
        // and hence a margin is needed to constrain on x, to get the scale, we then center it along y
        newScale = (canvasSize.width - 2 * preferredHorizontalMargin) / childSize!.width;
        break;
    }

    final marginOffset = ((canvasSize.toOffset() - (childSize! * scale).toOffset()) / (2 * scale)).makeAtleast(0);
    newGsTopLeft = childInfo.gsPosition - marginOffset;

    if (animate) {
      animateToOffsetAndScale(offset: newGsTopLeft, duration: duration, scale: newScale);
    } else {
      _gsTopLeftOffset = newGsTopLeft;
      _scale = newScale;
      notifyListeners();
    }
  }

  // ==================== Animation ====================

  /// Animate the canvas to a new offset and scale
  Future<void> animateToOffsetAndScale({
    required Offset offset,
    required double scale,
    Duration? duration,
    Curve curve = Curves.easeInOut,
  }) async {
    final anim = AnimationController(vsync: _ticker!, duration: duration ?? defaultAnimationDuration);
    final offsetTween = Tween<Offset>(begin: _gsTopLeftOffset, end: offset);
    final scaleTween = Tween<double>(begin: _scale, end: scale);

    final offsetAnimation = offsetTween.animate(CurvedAnimation(parent: anim, curve: curve));
    final scaleAnimation = scaleTween.animate(CurvedAnimation(parent: anim, curve: curve));

    anim.addListener(() {
      _gsTopLeftOffset = offsetAnimation.value;
      _scale = scaleAnimation.value;
      notifyListeners();
    });

    await anim.forward();
    anim.dispose();
  }
}
