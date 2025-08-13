part of 'controller.dart';

// ------------------------------ Private Types ------------------------------

// some simple exceptions
// ignore: non_constant_identifier_names
final _ChildNotFoundException = Exception('Child with the given ID does not exist');

class _ChildInfo {
  Offset gsPosition;
  Size? lastRenderedSize;
  final Widget widget;

  _ChildInfo({required this.gsPosition, required this.widget, this.lastRenderedSize});
}

class ChildInfo {
  CanvasChildId id;
  Offset gsPosition;
  Offset ssPosition;
  Widget child;
  ChildInfo({required this.id, required this.gsPosition, required this.ssPosition, required this.child});
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
  CanvasChildId? id;

  CanvasChildArgs({required this.position, required this.widget, this.childSize, this.id});
}
