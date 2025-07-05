import 'dart:math';
import 'dart:ui' show Offset;

extension OffsetCartesionOps on Offset {
  double distanceSquared(Offset other) {
    final dx = this.dx - other.dx;
    final dy = this.dy - other.dy;
    return dx * dx + dy * dy;
  }

  Offset operator -(Offset other) {
    return Offset(dx - other.dx, dy - other.dy);
  }

  Point toPoint() {
    return Point(dx, dy);
  }

  String coord() {
    return '(${dx.toStringAsFixed(2)}, ${dy.toStringAsFixed(2)})';
  }
}
