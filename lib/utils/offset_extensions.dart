import 'dart:math';
import 'dart:ui' show Offset;

extension OffsetCartesionOps on Offset {
  double distanceSquared(Offset other) {
    final dx = this.dx - other.dx;
    final dy = this.dy - other.dy;
    return dx * dx + dy * dy;
  }

  Offset operator +(Offset other) {
    return Offset(dx + other.dx, dy + other.dy);
  }

  Offset operator -(Offset other) {
    return Offset(dx - other.dx, dy - other.dy);
  }

  Offset operator *(double scalar) {
    return Offset(dx * scalar, dy * scalar);
  }

  Offset makeAtleast(double value) {
    return Offset(dx < value ? value : dx, dy < value ? value : dy);
  }

  Offset operator /(double scalar) {
    if (scalar == 0) {
      throw ArgumentError('Division by zero is not allowed.');
    }
    return Offset(dx / scalar, dy / scalar);
  }

  Point toPoint() {
    return Point(dx, dy);
  }

  String coord() {
    return '(${dx.toStringAsFixed(2)}, ${dy.toStringAsFixed(2)})';
  }
}
