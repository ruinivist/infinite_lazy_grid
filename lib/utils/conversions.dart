import 'dart:ui';

/// Convert grid space coordinates to screen space coordinates
Offset gsToSs(Offset gsPosition, Offset gsTopLeft) {
  return gsPosition - gsTopLeft;
}

/// Convert screen space coordinates to grid space coordinates
Offset ssToGs(Offset ssPosition, Offset gsTopLeft) {
  return ssPosition + gsTopLeft;
}
