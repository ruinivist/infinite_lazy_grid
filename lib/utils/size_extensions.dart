import 'package:flutter/material.dart';

extension SizeOps on Size {
  Size operator /(double scalar) {
    if (scalar == 0) {
      throw ArgumentError('Division by zero is not allowed.');
    }
    return Size(width / scalar, height / scalar);
  }

  Size operator *(double scalar) {
    return Size(width * scalar, height * scalar);
  }

  Offset toOffset() {
    return Offset(width, height);
  }
}
