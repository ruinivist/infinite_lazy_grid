import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
import 'package:infinite_lazy_grid/core/background.dart';
import '../../utils/measure_size.dart';
import '../spatial_hashing.dart';
import '../../utils/conversions.dart';
import '../render.dart';
import 'package:uuid/uuid.dart';

part 'types.dart';

/// Controller for [LazyCanvas]
class LazyCanvasController with ChangeNotifier {
  final Uuid _uuid = Uuid();
  Offset _gsTopLeftOffset = Offset.zero;
  double _baseScale = 1, _scale = 1;
  late Size _canvasSize;
  final Map<CanvasChildId, _ChildInfo> _children = {}; // CanvasChildId for IDs
  var _nextPaintOrder = 0;
  bool _init = false;
  final SpatialHashing<CanvasChildId> _spatialHash;
  TickerProvider? _ticker;
  AnimationController? _activeAnimation;
  bool _scaledDuringGesture = false;
  late BuildContext _context;
  CanvasChildId?
  _focusChildOnBuild; // if set, will focus on this child on the next render
  CanvasBackground _background;
  // these are used to cache result of widgetsWithScreenPositions
  List<ChildInfo> _lastRenderedWidgets = [];
  Offset? _lastProcessedOffset;
  double? _lastProcessedScale;
  bool _markDirty =
      false; // do any of the non scale or offset changes require a rebuild?
  final bool useIdsFromArgs;
  OnWidgetEnteredRender? onWidgetEnteredRender;
  OnWidgetExitedRender? onWidgetExitedRender;
  Set<CanvasChildId> _renderedWidgets =
      {}; // to track which widgets are currently rendered
  PointerDownEventListener? rawPointerDownListener;
  PointerMoveEventListener? rawPointerMoveListener;
  PointerUpEventListener? rawPointerUpListener;
  PointerCancelEventListener? rawPointerCancelListener;
  PointerSignalEventListener? rawPointerSignalListener;

  bool debug;
  final Duration defaultAnimationDuration;
  final bool inertiaEnabled;
  final double inertiaFrictionCoefficient;
  final double buildExtentMultiplier;

  LazyCanvasController({
    this.debug = false,
    this.buildExtentMultiplier = 2,
    Size hashCellSize = const Size(100, 100),
    this.defaultAnimationDuration = const Duration(milliseconds: 300),
    this.inertiaEnabled = true,
    this.inertiaFrictionCoefficient = 0.0000135,
    CanvasBackground background = const DotGridBackground(),
    this.useIdsFromArgs = false,
    this.onWidgetEnteredRender,
    this.onWidgetExitedRender,
    this.rawPointerSignalListener,
    this.rawPointerDownListener,
    this.rawPointerMoveListener,
    this.rawPointerUpListener,
    this.rawPointerCancelListener,
  }) : assert(buildExtentMultiplier >= 1),
       assert(inertiaFrictionCoefficient > 0 && inertiaFrictionCoefficient < 1),
       _background = background,
       _spatialHash = SpatialHashing<CanvasChildId>(cellSize: hashCellSize);
  // only top left is considered so if a widget has long width, it'll not be rendered
  // unless the cache extent is sufficient

  // ==================== Getters ====================
  Offset get offset => _gsTopLeftOffset;
  double get scale => _scale;
  Size get canvasSize => _canvasSize;
  Offset get _ssCenter => Offset(_canvasSize.width / 2, _canvasSize.height / 2);
  Offset get _gsCenter => ssToGs(_ssCenter, _gsTopLeftOffset, _scale);
  bool get _renderCacheDirty =>
      _lastProcessedOffset != _gsTopLeftOffset ||
      _lastProcessedScale != _scale ||
      _markDirty;
  Offset get buildExtent =>
      Offset(_canvasSize.width, _canvasSize.height) /
      _scale *
      buildExtentMultiplier;
  CanvasBackground get background => _background;

  /// Immutable back-to-front snapshot of all children, including culled children.
  List<CanvasChildId> get childOrder => List.unmodifiable(
    _children.keys.toList()..sort(
      (a, b) => _children[a]!.paintOrder.compareTo(_children[b]!.paintOrder),
    ),
  );

  set background(CanvasBackground value) {
    if (identical(_background, value)) return;
    _background = value;
    markDirty();
  }

  // ==================== Callback Functions ====================

  /// Update the canvas size when the widget size changes.
  void onCanvasSizeChange(Size size) {
    if (size == Size.zero) {
      return; // ignore the zero side, linux first build pass error
    }
    if (_init && size == _canvasSize) return;

    _canvasSize = size; // allow resize due to canvas resize
    _init = true;
    Future.microtask(markDirty);
  }

  /// Called when a child widget's size changes.
  void onChildSizeChange(CanvasChildId id, Size size) {
    _children[id]!.lastRenderedSize = size;
  }

  /// Set the ticker provider for animations.
  void setTickerProvider(TickerProvider? ticker) {
    if (ticker == null) stopAnimation();
    _ticker = ticker;
  }

  void setBuildContext(BuildContext context) {
    _context = context;
  }

  // ==================== Utils ====================

  void markDirty() {
    _markDirty = true;
    // this is done instead of just notifyListeners() so as to differentiate
    // betweena adhoc calls to widgetsWithScreenPositions
    // if you need to call notifyListeners() from within this class,
    // it should always be with markDirty()
    notifyListeners();
  }

  // ==================== Child Management ====================

  /// Add a child at a given position with a widget. Returns the child ID.
  /// You need the child size for optimising the focus on child
  /// [rotation] is clockwise radians around the layout center.
  CanvasChildId addChild(
    Offset position,
    Widget widget, {
    Size? childSize,
    double rotation = 0,
    CanvasChildId? id,
  }) {
    final childId = _addChildInternal(
      position,
      widget,
      childSize: childSize,
      rotation: rotation,
      id: id,
    );
    markDirty();
    return childId;
  }

  CanvasChildId _addChildInternal(
    Offset position,
    Widget widget, {
    Size? childSize,
    double rotation = 0,
    CanvasChildId? id,
  }) {
    _validateGeometry(
      position: position,
      rotation: rotation,
      childSize: childSize,
    );
    assert(!useIdsFromArgs || useIdsFromArgs && id != null);
    id ??= _uuid.v4();
    _children[id] = _ChildInfo(
      gsPosition: position,
      rotation: rotation,
      widget: widget,
      lastRenderedSize: childSize,
      paintOrder: _nextPaintOrder++,
    );
    _spatialHash.add(
      Point(position.dx, position.dy),
      id,
    ); // add to spatial hash
    return id;
  }

  List<CanvasChildId> addChildren(
    List<CanvasChildArgs> children, {
    CanvasChildId? focusOnBuild,
  }) {
    for (final child in children) {
      _validateGeometry(
        position: child.position,
        rotation: child.rotation,
        childSize: child.childSize,
      );
    }
    final ids = <CanvasChildId>[];
    for (final child in children) {
      ids.add(
        _addChildInternal(
          child.position,
          child.widget,
          childSize: child.childSize,
          rotation: child.rotation,
          id: child.id,
        ),
      );
    }
    _focusChildOnBuild = focusOnBuild;
    markDirty();
    return ids;
  }

  /// Remove a child by its ID.
  void removeChild(CanvasChildId id) {
    final child = _children[id];
    if (child == null) {
      throw _ChildNotFoundException;
    }
    final position = child.gsPosition;
    _spatialHash.remove(Point(position.dx, position.dy), id);
    _children.remove(id);
    markDirty();
  }

  /// Remove all children. Does not change where you are on the canvas.
  void clear() {
    _children.clear();
    _spatialHash.clear();
    _nextPaintOrder = 0;
    markDirty();
  }

  // ==================== Child Ordering ====================

  /// Checks whether [action] would change order, without notifying or mutating.
  /// Targets are deduplicated and all IDs are validated, as in the commands.
  /// Forward/backward throw [StateError] if a required layout size is unknown.
  bool canArrange(Iterable<CanvasChildId> ids, CanvasArrange action) =>
      _arrangedOrder(ids, action) != null;

  /// Moves the bundle above the nearest overlapping unselected child above it.
  /// Preserves target and non-target relative order; see [canArrange] for errors.
  bool bringForward(Iterable<CanvasChildId> ids) =>
      _arrange(ids, CanvasArrange.forward);

  /// Moves the bundle below the nearest overlapping unselected child below it.
  /// Preserves target and non-target relative order; see [canArrange] for errors.
  bool sendBackward(Iterable<CanvasChildId> ids) =>
      _arrange(ids, CanvasArrange.backward);

  /// Paints and hit tests the ordered bundle above all other children.
  /// Returns whether order changed; changed commands notify exactly once.
  bool bringToFront(Iterable<CanvasChildId> ids) =>
      _arrange(ids, CanvasArrange.front);

  /// Paints and hit tests the ordered bundle below all other children.
  /// Returns whether order changed; changed commands notify exactly once.
  bool sendToBack(Iterable<CanvasChildId> ids) =>
      _arrange(ids, CanvasArrange.back);

  bool _arrange(Iterable<CanvasChildId> ids, CanvasArrange action) {
    final order = _arrangedOrder(ids, action);
    if (order == null) return false;
    for (var index = 0; index < order.length; index++) {
      _children[order[index]]!.paintOrder = index;
    }
    _nextPaintOrder = order.length;
    markDirty();
    return true;
  }

  List<CanvasChildId>? _arrangedOrder(
    Iterable<CanvasChildId> ids,
    CanvasArrange action,
  ) {
    final targets = ids.toSet();
    for (final id in targets) {
      _requireChild(id);
    }
    if (targets.isEmpty) return null;
    final order = childOrder;
    final bundle = order.where(targets.contains).toList();
    final others = order.where((id) => !targets.contains(id)).toList();
    var insertion = action == CanvasArrange.front ? others.length : 0;
    if (action == CanvasArrange.forward || action == CanvasArrange.backward) {
      final forward = action == CanvasArrange.forward;
      final step = forward ? 1 : -1;
      final boundary = order.indexOf(forward ? bundle.last : bundle.first);
      if (boundary + step < 0 || boundary + step >= order.length) return null;
      final footprints = bundle.map(_childFootprint).toList();
      CanvasChildId? crossed;
      for (
        var index = boundary + step;
        index >= 0 && index < order.length;
        index += step
      ) {
        final candidate = order[index];
        if (targets.contains(candidate)) continue;
        final footprint = _childFootprint(candidate);
        if (footprints.any(
          (path) =>
              path.getBounds().overlaps(footprint.getBounds()) &&
              !Path.combine(
                PathOperation.intersect,
                path,
                footprint,
              ).getBounds().isEmpty,
        )) {
          crossed = candidate;
          break;
        }
      }
      if (crossed == null) return null;
      insertion = others.indexOf(crossed) + (forward ? 1 : 0);
    }
    final result = others..insertAll(insertion, bundle);
    return listEquals(order, result) ? null : result;
  }

  Path _childFootprint(CanvasChildId id) {
    final child = _children[id]!;
    final size = child.lastRenderedSize;
    if (size == null) {
      throw StateError('Layout size is unknown for child "$id"');
    }
    return (Path()..addRect(Offset.zero & size)).transform(
      childTransform(child.gsPosition, size, child.rotation).storage,
    );
  }

  // ==================== Child Updates ====================

  /// Read a snapshot without building or laying out the child.
  ChildInfo getInfo(CanvasChildId id) {
    final child = _requireChild(id);
    return ChildInfo(
      id: id,
      gsPosition: child.gsPosition,
      ssPosition: gsToSs(child.gsPosition, _gsTopLeftOffset, _scale),
      rotation: child.rotation,
      childSize: child.lastRenderedSize,
      child: child.widget,
    );
  }

  /// Apply supplied fields atomically. Null fields leave existing values unchanged.
  /// Returns whether anything changed; changed updates notify exactly once.
  /// [rotation] is clockwise radians around the layout center.
  bool update(
    CanvasChildId id, {
    Offset? position,
    double? rotation,
    Size? childSize,
    Widget? widget,
  }) {
    final child = _requireChild(id);
    _validateGeometry(
      position: position,
      rotation: rotation,
      childSize: childSize,
    );
    final changed = _updateChild(
      child,
      id,
      position: position,
      rotation: rotation,
      childSize: childSize,
      widget: widget,
    );
    if (changed) markDirty();
    return changed;
  }

  /// Move a child by [gridDelta] in canvas coordinates. Returns the child ID.
  CanvasChildId moveChildBy(CanvasChildId id, Offset gridDelta) {
    update(id, position: _requireChild(id).gsPosition + gridDelta);
    return id;
  }

  /// Move unique children together, validating every resulting position first.
  void moveChildrenBy(Iterable<CanvasChildId> ids, Offset gridDelta) {
    _validateGeometry(position: gridDelta);
    final positions = <CanvasChildId, Offset>{};
    for (final id in ids.toSet()) {
      final position = _requireChild(id).gsPosition + gridDelta;
      _validateGeometry(position: position);
      positions[id] = position;
    }
    var changed = false;
    for (final entry in positions.entries) {
      changed =
          _updateChild(
            _children[entry.key]!,
            entry.key,
            position: entry.value,
          ) ||
          changed;
    }
    if (changed) markDirty();
  }

  _ChildInfo _requireChild(CanvasChildId id) =>
      _children[id] ?? (throw _ChildNotFoundException);

  void _validateGeometry({
    Offset? position,
    double? rotation,
    Size? childSize,
  }) {
    if (position != null && (!position.dx.isFinite || !position.dy.isFinite)) {
      throw ArgumentError.value(position, 'position', 'Must be finite');
    }
    if (rotation != null && !rotation.isFinite) {
      throw ArgumentError.value(rotation, 'rotation', 'Must be finite');
    }
    if (childSize != null &&
        (!childSize.width.isFinite ||
            !childSize.height.isFinite ||
            childSize.width < 0 ||
            childSize.height < 0)) {
      throw ArgumentError.value(
        childSize,
        'childSize',
        'Must be finite and nonnegative',
      );
    }
  }

  bool _updateChild(
    _ChildInfo child,
    CanvasChildId id, {
    Offset? position,
    double? rotation,
    Size? childSize,
    Widget? widget,
  }) {
    final positionChanged = position != null && position != child.gsPosition;
    final sizeChanged =
        childSize != null && childSize != child.lastRenderedSize;
    final rotationChanged = rotation != null && rotation != child.rotation;
    final widgetChanged = widget != null && widget != child.widget;
    if (!positionChanged &&
        !sizeChanged &&
        !rotationChanged &&
        !widgetChanged) {
      return false;
    }
    if (positionChanged) {
      final oldPosition = child.gsPosition;
      _spatialHash.remove(Point(oldPosition.dx, oldPosition.dy), id);
      child.gsPosition = position;
      _spatialHash.add(Point(position.dx, position.dy), id);
    }
    child.lastRenderedSize = childSize ?? child.lastRenderedSize;
    child.rotation = rotation ?? child.rotation;
    child.widget = widget ?? child.widget;
    return true;
  }

  /// Called when a scale gesture starts.
  void onScaleStart(ScaleStartDetails details) {
    stopAnimation();
    _baseScale = _scale;
    _scaledDuringGesture = false;
  }

  /// Called when a scale gesture updates.
  /// Usually you would not want to override this
  void onScaleUpdate(ScaleUpdateDetails details) {
    // uses usual display conventions and final vector postion - initial vector position
    // convention is that if I drag from right to left, dx is negative
    // for top to bottom, dy is postive

    // scale + offset => scale then offset

    final newScale = _baseScale * details.scale;
    if (newScale != _scale) {
      _scaledDuringGesture = true;
      _gsTopLeftOffset = newGsTopLeftOnScaling(
        _gsTopLeftOffset,
        details.localFocalPoint - details.focalPointDelta,
        _scale,
        newScale,
      );
      _scale = newScale;
    }

    if (details.focalPointDelta != Offset.zero) {
      // if ss distnace is x, and zoom is 2x, gs only moves by x/2
      _gsTopLeftOffset -= details.focalPointDelta / _scale;
    }

    markDirty();
  }

  /// Called when a scale gesture ends.
  void onScaleEnd(ScaleEndDetails details) {
    if (!inertiaEnabled || _scaledDuringGesture || _ticker == null) return;

    final velocity = details.velocity.pixelsPerSecond;
    final speed = velocity.distance;
    if (speed < kMinFlingVelocity) return;

    stopAnimation();
    final direction = velocity / speed;
    var lastPosition = 0.0;
    final animation = AnimationController.unbounded(vsync: _ticker!);
    _activeAnimation = animation;
    animation.addListener(() {
      final delta = animation.value - lastPosition;
      lastPosition = animation.value;
      _gsTopLeftOffset -= direction * delta / _scale;
      markDirty();
    });
    animation
        .animateWith(FrictionSimulation(inertiaFrictionCoefficient, 0, speed))
        .whenCompleteOrCancel(() => _disposeAnimation(animation));
  }

  /// Scroll the viewport by a screen-space pointer delta.
  void scrollBy(Offset screenDelta) {
    stopAnimation();
    _gsTopLeftOffset += screenDelta / _scale;
    markDirty();
  }

  /// Increment or decrement the scale by an additive delta value.
  void updateScalebyDelta(double delta, {Offset? focalPoint}) {
    stopAnimation();
    // added focalPoint param
    focalPoint ??= Offset(canvasSize.width / 2, canvasSize.height / 2);
    final newScale = _scale + delta;
    _gsTopLeftOffset = newGsTopLeftOnScaling(
      _gsTopLeftOffset,
      focalPoint,
      _scale,
      newScale,
    );
    _scale = newScale;
    markDirty();
  }

  /// Returns true if the child exists, false otherwise.
  bool hasChild(CanvasChildId id) {
    return _children.containsKey(id);
  }

  // ==================== Positioning Logic ====================

  /// Currently rendered widgets with their position info
  List<ChildInfo> widgetsWithScreenPositions({bool forceRebuild = false}) {
    if (!_init) return [];

    if (_focusChildOnBuild != null) {
      // if this is the first build, focus on the child if set
      focusOnChild(_focusChildOnBuild!, animate: false);
      _focusChildOnBuild = null;
    }

    // _renderCacheDirty depends on _markDirty + other stuff
    if (!_renderCacheDirty && !forceRebuild) {
      // if the render cache is not dirty, we can use the cached result
      return _lastRenderedWidgets;
    }

    _lastProcessedOffset = _gsTopLeftOffset;
    _lastProcessedScale = _scale;
    _markDirty = false;

    final idsToBuild = _childrenWithinBuildArea(_gsCenter, buildExtent);

    // do the needed callbacks
    if (onWidgetEnteredRender != null || onWidgetExitedRender != null) {
      final newRenderedWidgets = idsToBuild.toSet();
      final exitedWidgets = _renderedWidgets.difference(newRenderedWidgets);
      final enteredWidgets = newRenderedWidgets.difference(_renderedWidgets);

      Future.microtask(() {
        // so that the build is not blocked
        for (final id in exitedWidgets) {
          onWidgetExitedRender?.call(id);
        }
        for (final id in enteredWidgets) {
          onWidgetEnteredRender?.call(id);
        }
      });
    }
    _renderedWidgets = idsToBuild.toSet();

    return _lastRenderedWidgets = idsToBuild.map(getInfo).toList();
  }

  List<CanvasChildId> _childrenWithinBuildArea(Offset center, Offset extent) {
    Offset halfExtent = Offset(
      (extent.dx / 2).ceilToDouble(),
      (extent.dy / 2).ceilToDouble(),
    );
    final items = _spatialHash.getPointsAround(
      Point(center.dx, center.dy),
      halfExtent,
    );
    return items.map((item) => item.data).toList()..sort(
      (a, b) => _children[a]!.paintOrder.compareTo(_children[b]!.paintOrder),
    );
  }

  // ==================== Centering & Focus Functions ====================

  /// Center the canvas so that the given screen-space offset is at the center of the viewport.
  void centerOnScreenOffset(
    Offset ssOffset, {
    Duration? duration,
    bool animate = true,
  }) {
    centerOnGridOffset(
      ssToGs(ssOffset, _gsTopLeftOffset, _scale),
      animate: animate,
    );
  }

  /// Center the canvas so that the given grid-space offset is at the center of the viewport.
  void centerOnGridOffset(
    Offset gsOffset, {
    Duration? duration,
    bool animate = true,
  }) {
    // if 2x scale you need to adjust lesser
    final newGsTopLeft =
        gsOffset + (canvasSize * (2 * scale)).bottomRight(Offset.zero);
    if (animate) {
      animateToOffsetAndScale(
        offset: newGsTopLeft,
        duration: duration,
        scale: _scale,
      );
    } else {
      stopAnimation();
      _gsTopLeftOffset = newGsTopLeft;
      markDirty();
    }
  }

  /// Focus the viewport on a child by its ID, with a margin in screen-space.
  /// If it's already rendered, size will be picked up from the child widget. If not
  /// an offstage rendering will be used ( double render )
  /// Preferred horizontal margin used for [ScalingMode.fitInViewport].
  /// Fits rotated bounds in both viewport dimensions and centers using the resulting scale.
  void focusOnChild(
    CanvasChildId id, {
    ScalingMode scalingMode = ScalingMode.keepScale,
    bool animate = true,
    double preferredHorizontalMargin = 16,
    Duration? duration,
    Size? childSize,
    forceRedraw = false,
  }) {
    final childInfo = _requireChild(id);

    // try to figure out the size, take from render cache if available
    // else do an offstage render
    childSize ??= childInfo.lastRenderedSize != null && !forceRedraw
        ? childInfo.lastRenderedSize
        : measureWidgetSize(_context, childInfo.widget);

    _validateGeometry(childSize: childSize);
    _updateChild(childInfo, id, childSize: childSize);
    _markDirty = true;

    final bounds = MatrixUtils.transformRect(
      childTransform(childInfo.gsPosition, childSize!, childInfo.rotation),
      Offset.zero & childSize,
    );

    /*
    margin is symmetric on ltrb so
    2mx + cx = screenWidth
    2my + cy = screenHeight
    where c is rotated bounds size in screen space at newScale and m is margin
    centering in grid space is childCenter - screenCenter / newScale
    */

    double newScale = _scale;

    switch (scalingMode) {
      case ScalingMode.keepScale:
        // do nothing
        break;
      case ScalingMode.resetScale:
        newScale = 1;
      case ScalingMode.fitInViewport:
        // the scale needs to be determined in this case
        // the horizontal margin constrains x, viewport height constrains y; use the smaller scale
        final horizontalScale = bounds.width == 0
            ? double.infinity
            : (canvasSize.width - 2 * preferredHorizontalMargin) / bounds.width;
        final verticalScale = bounds.height == 0
            ? double.infinity
            : canvasSize.height / bounds.height;
        final fitScale = min(horizontalScale, verticalScale);
        if (fitScale.isFinite && fitScale > 0) newScale = fitScale;
        break;
    }

    final newGsTopLeft = bounds.center - _ssCenter / newScale;

    if (animate) {
      animateToOffsetAndScale(
        offset: newGsTopLeft,
        duration: duration,
        scale: newScale,
      );
    } else {
      stopAnimation();
      _gsTopLeftOffset = newGsTopLeft;
      _scale = newScale;
      markDirty();
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
    stopAnimation();
    final anim = AnimationController(
      vsync: _ticker!,
      duration: duration ?? defaultAnimationDuration,
    );
    _activeAnimation = anim;
    final offsetTween = Tween<Offset>(begin: _gsTopLeftOffset, end: offset);
    final scaleTween = Tween<double>(begin: _scale, end: scale);

    final curvedAnimation = CurvedAnimation(parent: anim, curve: curve);
    final offsetAnimation = offsetTween.animate(curvedAnimation);
    final scaleAnimation = scaleTween.animate(curvedAnimation);

    anim.addListener(() {
      _gsTopLeftOffset = offsetAnimation.value;
      _scale = scaleAnimation.value;
      markDirty();
    });

    try {
      await anim.forward().orCancel;
    } on TickerCanceled {
      // A new interaction replaced this animation.
    } finally {
      curvedAnimation.dispose();
      _disposeAnimation(anim);
    }
  }

  /// Stops inertia or an animated viewport transition at its current position.
  void stopAnimation() {
    final animation = _activeAnimation;
    _activeAnimation = null;
    animation?.dispose();
  }

  void _disposeAnimation(AnimationController animation) {
    if (_activeAnimation == animation) stopAnimation();
  }
}
