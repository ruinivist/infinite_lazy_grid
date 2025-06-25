import 'dart:ui' show Offset;

extension OffsetCartesionOps on Offset {
  double distanceSquared(Offset other) {
    final dx = this.dx - other.dx;
    final dy = this.dy - other.dy;
    return dx * dx + dy * dy;
  }
}
