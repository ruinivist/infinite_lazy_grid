import 'package:flutter/rendering.dart';

/// Convert grid space coordinates to screen space coordinates
Offset gsToSs(Offset gsPosition, Offset gsTopLeft, double scale) {
  return (gsPosition - gsTopLeft) * scale;
}

/// Convert screen space coordinates to grid space coordinates
Offset ssToGs(Offset ssPosition, Offset gsTopLeft, double scale) {
  return ssPosition / scale + gsTopLeft;
}

Offset newGsTopLeftOnScaling(
  Offset gsTopLeft,
  Offset ssFocalPoint,
  double oldScale,
  double newScale,
) {
  // gsFocal remains same
  // we change gsTopLeft to keep ssFocalPoint same as well
  Offset gsFocalPoint = ssToGs(ssFocalPoint, gsTopLeft, oldScale);
  return gsFocalPoint - ssFocalPoint / newScale;
}

/// Maps local child coordinates to the parent, rotating around the layout center.
/// Used by painting, pointer targeting, coordinate conversion and focus bounds.
Matrix4 childTransform(
  Offset position,
  Size size,
  double rotation, {
  double scale = 1,
}) {
  final transform = Matrix4.identity()
    ..translateByDouble(position.dx, position.dy, 0, 1)
    ..scaleByDouble(scale, scale, 1, 1);
  if (rotation != 0) {
    final center = size.center(Offset.zero);
    transform
      ..translateByDouble(center.dx, center.dy, 0, 1)
      ..rotateZ(rotation)
      ..translateByDouble(-center.dx, -center.dy, 0, 1);
  }
  return transform;
}
