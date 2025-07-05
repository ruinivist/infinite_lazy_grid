import 'dart:ui';

/// Convert grid space coordinates to screen space coordinates
Offset gsToSs(Offset gsPosition, Offset gsTopLeft, double scale) {
  return (gsPosition - gsTopLeft) * scale;
}

/// Convert screen space coordinates to grid space coordinates
Offset ssToGs(Offset ssPosition, Offset gsTopLeft, double scale) {
  return ssPosition / scale + gsTopLeft;
}

Offset newGsTopLeftOnScaling(Offset gsTopLeft, Offset ssFocalPoint, double oldScale, double newScale) {
  // gsFocal remains same
  // we change gsTopLeft to keep ssFocalPoint same as well
  Offset gsFocalPoint = ssToGs(ssFocalPoint, gsTopLeft, oldScale);
  return gsFocalPoint - ssFocalPoint / newScale;
}
