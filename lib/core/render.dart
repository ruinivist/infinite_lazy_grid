import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'background.dart';

/**
 * Working of some of the flutter code used here:

 */

/// An infinite canvas that places all the children at the specified positions.
class CanvasView extends StatelessWidget {
  final List<Offset> ssPositions; // screen space positions;
  final List<Widget> children; // children, in the same order as positions
  final CanvasBackground canvasBackground;

  const CanvasView({required this.ssPositions, required this.children, required this.canvasBackground, super.key})
    : assert(children.length == ssPositions.length, 'Children and positions must have the same length');

  @override
  Widget build(BuildContext context) {
    return Container(
      color: canvasBackground.bgColor,
      child: GestureDetector(
        child: _CanvasRenderObject(canvasBackground: canvasBackground, ssPositions: ssPositions, children: children),
      ),
    );
  }
}

/// A combined widget for all the render object of the children + background.
class _CanvasRenderObject extends MultiChildRenderObjectWidget {
  final List<Offset> ssPositions;
  final CanvasBackground canvasBackground;

  const _CanvasRenderObject({
    required this.ssPositions,
    required super.children, // children go to the MultiChildRenderObjectWidget
    required this.canvasBackground,
  }) : assert(ssPositions.length == children.length, 'Children and positions must have the same length');

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _CanvasRenderBox(ssPositions: ssPositions, canvasBackground: canvasBackground);
  }

  @override
  void updateRenderObject(BuildContext context, _CanvasRenderBox renderObject) {
    // static for now
  }
}

/// Dummy empty parent data for each child
class _WidgetParentData extends ContainerBoxParentData<RenderBox> {}

class _CanvasRenderBox extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _WidgetParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _WidgetParentData> {
  final CanvasBackground canvasBackground;
  final List<Offset> ssPositions;

  _CanvasRenderBox({required this.ssPositions, required this.canvasBackground});

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _WidgetParentData) {
      child.parentData = _WidgetParentData();
    }
  }

  @override
  void performLayout() {
    size = constraints.biggest; // expand as much as possible for the parent

    RenderBox? child = firstChild;

    while (child != null) {
      final _WidgetParentData parentData = child.parentData! as _WidgetParentData;
      // loosen so like a stack can take it's own size inside parent
      // like a stack parent is not using size and is always expanded hence the second arg
      child.layout(constraints.loosen(), parentUsesSize: false);
      child = parentData.nextSibling;
    }
  }

  @override
  void paint(PaintingContext context, Offset canvasStartOffset) {
    final canvas = context.canvas;

    // use the canvas background painter, pass it the canvas and that should handle drawing the background
    canvasBackground.paint(canvas, size);

    RenderBox? child = firstChild;
    for (int idx = 0; child != null; idx++) {
      final _WidgetParentData parentData = child.parentData! as _WidgetParentData;
      context.paintChild(child, ssPositions[idx]);
      child = parentData.nextSibling;
    }
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final ssHitPosition = position;

    if (!size.contains(ssHitPosition)) {
      return false;
    }

    // Check children in reverse order (last painted = first hit)
    RenderBox? child = lastChild;
    for (int idx = ssPositions.length - 1; child != null; idx--) {
      final _WidgetParentData parentData = child.parentData! as _WidgetParentData;

      // Transform the hit position relative to the child's position
      final childPosition = ssHitPosition - ssPositions[idx];

      if (child.hitTest(BoxHitTestResult.wrap(result), position: childPosition)) {
        return true;
      }

      child = parentData.previousSibling;
    }

    // If no child was hit, the canvas itself handles the hit
    result.add(BoxHitTestEntry(this, ssHitPosition));
    return true;
  }
}
