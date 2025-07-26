import 'package:flutter/material.dart';

/// Utility to synchronously measure the size of a widget by building it offscreen in an Overlay.
/// Only works for widgets with deterministic, constraint-based sizing (no async/layout dependencies).
Size measureWidgetSize(BuildContext context, Widget child, {BoxConstraints? constraints}) {
  final key = GlobalKey();
  final overlay = Overlay.of(context);
  Size? measuredSize;

  final widget = Offstage(
    child: ConstrainedBox(
      constraints: constraints ?? const BoxConstraints(),
      child: Container(key: key, child: child),
    ),
  );

  final entry = OverlayEntry(builder: (_) => widget);
  overlay.insert(entry);

  WidgetsBinding.instance.handleDrawFrame();

  final ctx = key.currentContext;
  if (ctx != null) {
    measuredSize = (ctx.findRenderObject() as RenderBox).size;
  }
  entry.remove();
  return measuredSize ?? Size.zero;
}
