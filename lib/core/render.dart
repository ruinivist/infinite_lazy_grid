import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:infinite_lazy_2d_grid/core/controller.dart';
import 'package:infinite_lazy_2d_grid/utils/offset_extensions.dart';
import 'package:infinite_lazy_2d_grid/utils/styles.dart';

import 'background.dart';

/**
 * Working of some of the flutter code used here:

 */

/// An infinite canvas that places all the children at the specified positions.
class CanvasView extends StatelessWidget {
  final CanvasBackground canvasBackground;
  final CanvasController controller;

  const CanvasView({required this.controller, required this.canvasBackground, super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: canvasBackground.bgColor,
      child: GestureDetector(
        onScaleUpdate: controller.handleGesture,
        child: ListenableBuilder(
          listenable: controller,
          builder: (_, _) {
            final childrenWithPositions = controller.widgetsWithScreenPositions();
            final ssPositions = childrenWithPositions.map((e) => e.$1).toList();
            final children = childrenWithPositions.map((e) => e.$2).toList();
            final canvas = _CanvasRenderObject(
              canvasBackground: canvasBackground,
              ssPositions: ssPositions,
              children: children,
            );

            if (controller.debug) {
              return Stack(
                children: [
                  canvas,
                  Positioned(
                    top: 16,
                    left: 16,
                    child: Text('Offset: ${controller.offset.coord()}', style: monospaceStyle),
                  ),
                ],
              );
            } else {
              return canvas;
            }
          },
        ),
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
    renderObject
      ..ssPositions = ssPositions
      ..canvasBackground = canvasBackground;
  }
}

/// Dummy empty parent data for each child
class _WidgetParentData extends ContainerBoxParentData<RenderBox> {}

class _CanvasRenderBox extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _WidgetParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _WidgetParentData> {
  CanvasBackground _canvasBackground;
  List<Offset> _ssPositions;

  _CanvasRenderBox({required ssPositions, required canvasBackground})
    : _ssPositions = ssPositions,
      _canvasBackground = canvasBackground;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _WidgetParentData) {
      child.parentData = _WidgetParentData();
    }
  }

  set ssPositions(List<Offset> ssPositions) {
    if (_ssPositions != ssPositions) {
      _ssPositions = ssPositions;
      markNeedsPaint();
    }
  }

  set canvasBackground(CanvasBackground canvasBackground) {
    if (_canvasBackground != canvasBackground) {
      _canvasBackground = canvasBackground;
      markNeedsPaint();
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
    _canvasBackground.paint(canvas, size);

    RenderBox? child = firstChild;
    for (int idx = 0; child != null; idx++) {
      final _WidgetParentData parentData = child.parentData! as _WidgetParentData;
      context.paintChild(child, _ssPositions[idx]);
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
    for (int idx = _ssPositions.length - 1; child != null; idx--) {
      final _WidgetParentData parentData = child.parentData! as _WidgetParentData;

      // Transform the hit position relative to the child's position
      final childPosition = ssHitPosition - _ssPositions[idx];

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
