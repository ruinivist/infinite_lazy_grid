part of 'controller.dart';

// ------------------------------ Private Types ------------------------------

// some simple exceptions
// ignore: non_constant_identifier_names
final _ChildNotFoundException = Exception(
  'Child with the given ID does not exist',
);

class _ChildInfo {
  Offset gsPosition;
  Size? lastRenderedSize;
  double rotation;
  Widget widget;
  int paintOrder;

  _ChildInfo({
    required this.gsPosition,
    required this.widget,
    required this.paintOrder,
    required this.rotation,
    this.lastRenderedSize,
  });
}

/// An immutable child snapshot, available even when the child is culled.
/// [childSize] is the supplied or last measured, unrotated layout size in canvas units.
@immutable
class ChildInfo {
  final CanvasChildId id;

  /// Unrotated top-left in canvas/grid coordinates.
  final Offset gsPosition;

  /// Unrotated top-left in viewport/screen coordinates, including pan and zoom.
  /// With rotation, this is not the child's transformed local origin.
  final Offset ssPosition;

  /// Clockwise radians around the layout center.
  final double rotation;
  final Size? childSize;

  /// The widget supplied by the caller, without renderer wrappers.
  final Widget child;

  const ChildInfo({
    required this.id,
    required this.gsPosition,
    required this.ssPosition,
    required this.rotation,
    required this.childSize,
    required this.child,
  });
}

enum ScalingMode { resetScale, keepScale, fitInViewport }

typedef CanvasChildId = String;

// listener callbacks
typedef OnWidgetEnteredRender = void Function(CanvasChildId id);
typedef OnWidgetExitedRender = void Function(CanvasChildId id);

class CanvasChildArgs {
  final Offset position;
  final Widget widget;
  final Size? childSize;
  final double rotation;
  CanvasChildId? id;

  CanvasChildArgs({
    required this.position,
    required this.widget,
    this.childSize,
    this.rotation = 0,
    this.id,
  });
}
