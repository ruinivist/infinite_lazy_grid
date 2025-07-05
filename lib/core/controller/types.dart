part of 'controller.dart';

// ------------------------------ Private Types ------------------------------

// some simple exceptions
// ignore: non_constant_identifier_names
final _ChildNotFoundException = Exception('Child with the given ID does not exist');

class _ChildInfo {
  Offset gsPosition;
  Size? lastRenderedSize;
  final WidgetBuilder builder;

  _ChildInfo({required this.gsPosition, required this.builder});
}

class ChildInfo {
  int id;
  Offset gsPosition;
  Offset ssPosition;
  Widget child;
  ChildInfo({required this.id, required this.gsPosition, required this.ssPosition, required this.child});
}

enum ScalingMode { resetScale, keepScale, fitInViewport }
