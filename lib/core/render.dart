import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../utils/offset_extensions.dart';

import '../utils/styles.dart';
import 'background.dart';
import 'controller/controller.dart';

/// An infinite canvas that places all the children at the specified positions.
/// Needs a [LazyCanvasController] to control the canvas and a [CanvasBackground] to draw the background.
class LazyCanvas extends StatefulWidget {
  final CanvasBackground canvasBackground;
  final LazyCanvasController controller;

  const LazyCanvas({required this.controller, required this.canvasBackground, super.key});

  @override
  State<LazyCanvas> createState() => _LazyCanvasState();
}

class _LazyCanvasState extends State<LazyCanvas> with TickerProviderStateMixin<LazyCanvas> {
  @override
  void initState() {
    super.initState();
    widget.controller.setTickerProvider(this);
  }

  @override
  void dispose() {
    widget.controller.dispose(); // for the change notifier
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onScaleUpdate: widget.controller.onScaleUpdate,
      onScaleStart: widget.controller.onScaleStart,
      child: ListenableBuilder(
        listenable: widget.controller,
        builder: (_, _) {
          final childrenWithPositions = widget.controller.widgetsWithScreenPositions(context);
          final ssPositions = childrenWithPositions.map((e) => e.ssPosition).toList();
          final childrenIds = childrenWithPositions.map((e) => e.id).toList();
          final children = childrenWithPositions.map((e) => e.child).toList();
          final canvas = _CanvasRenderObject(
            childrenIds: childrenIds,
            canvasBackground: widget.canvasBackground,
            ssPositions: ssPositions,
            scale: widget.controller.scale,
            gridSpaceOffset: widget.controller.offset,
            onCanvasSizeChange: widget.controller.onCanvasSizeChange,
            onChildSizeChange: widget.controller.onChildSizeChange,
            children: children,
          );

          if (widget.controller.debug) {
            return Stack(
              children: [
                canvas,
                Positioned(
                  top: 16,
                  left: 16,
                  child: Text(
                    'Offset: ${widget.controller.offset.coord()}\nScale: ${widget.controller.scale.toStringAsFixed(1)}',
                    style: monospaceStyle,
                  ),
                ),
              ],
            );
          } else {
            return canvas;
          }
        },
      ),
    );
  }
}

/// A combined widget for all the render object of the children + background.
/// Everything is in screen space here
class _CanvasRenderObject extends MultiChildRenderObjectWidget {
  final List<int> childrenIds;
  final List<Offset> ssPositions;
  final double scale;
  final Offset gridSpaceOffset;
  final CanvasBackground canvasBackground;
  final Function onCanvasSizeChange;
  final Function onChildSizeChange;

  const _CanvasRenderObject({
    required this.childrenIds,
    required this.ssPositions,
    required this.scale,
    required this.gridSpaceOffset,
    required this.canvasBackground,
    required this.onCanvasSizeChange,
    required this.onChildSizeChange,
    required super.children, // children go to the MultiChildRenderObjectWidget
  }) : assert(ssPositions.length == children.length, 'Children and positions must have the same length'),
       assert(scale != 0);

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _CanvasRenderBox(
      childrenIds: childrenIds,
      ssPositions: ssPositions,
      scale: scale,
      gridSpaceOffset: gridSpaceOffset,
      canvasBackground: canvasBackground,
      onCanvasSizeChange: onCanvasSizeChange,
      onChildSizeChange: onChildSizeChange,
    );
  }

  @override
  void updateRenderObject(BuildContext context, _CanvasRenderBox renderObject) {
    renderObject
      ..childrenIds = childrenIds
      ..ssPositions = ssPositions
      ..canvasBackground = canvasBackground
      ..gridSpaceOffset = gridSpaceOffset
      ..scale = scale;
  }
}

class _CanvasWidgetParentData extends ContainerBoxParentData<RenderBox> {
  // there is already an "offset" defined in BoxParentdata that is exactly what I want
  late int id;
  late double scale; // scale is same for all rn but this makes it trivial to expand to children with diff scales
}

class _CanvasRenderBox extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _CanvasWidgetParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _CanvasWidgetParentData> {
  CanvasBackground _canvasBackground;
  List<int> _childrenIds;
  List<Offset> _ssPositions;
  Offset _gridSpaceOffset;
  double _scale;
  Function onCanvasSizeChange;
  Function onChildSizeChange;

  _CanvasRenderBox({
    required childrenIds,
    required ssPositions,
    required scale,
    required gridSpaceOffset,
    required canvasBackground,
    required this.onCanvasSizeChange,
    required this.onChildSizeChange,
  }) : assert(childrenIds.length == ssPositions.length),
       _childrenIds = childrenIds,
       _ssPositions = ssPositions,
       _scale = scale,
       _gridSpaceOffset = gridSpaceOffset,
       _canvasBackground = canvasBackground;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _CanvasWidgetParentData) {
      child.parentData = _CanvasWidgetParentData();
    }
  }

  set ssPositions(List<Offset> ssPositions) {
    // at this point childCount may not be equal to ssPositions.length
    // but since we are only marking for layout this is fine
    // at the actual performLayout this will be asserted
    if (_ssPositions != ssPositions) {
      _ssPositions = ssPositions;
      markNeedsLayout();
    }
  }

  set childrenIds(List<int> childrenIds) {
    if (_childrenIds != childrenIds) {
      _childrenIds = childrenIds;
    }
  }

  set scale(double scale) {
    if (_scale != scale) {
      _scale = scale;
      markNeedsLayout();
    }
  }

  set gridSpaceOffset(Offset gridSpaceOffset) {
    if (_gridSpaceOffset != gridSpaceOffset) {
      _gridSpaceOffset = gridSpaceOffset;
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
    assert(childCount == _ssPositions.length);
    size = constraints.biggest; // expand as much as possible for the parent
    onCanvasSizeChange(size); // notify the controller about the size

    RenderBox? child = firstChild;

    int index = 0;
    while (child != null) {
      final _CanvasWidgetParentData childParentData = child.parentData! as _CanvasWidgetParentData;
      childParentData.offset = _ssPositions[index];
      childParentData.id = _childrenIds[index];
      childParentData.scale = _scale;
      index++;
      // loosen so like a stack can take it's own size inside parent
      child.layout(constraints.loosen(), parentUsesSize: true);

      // notify the controller about the size of the child
      onChildSizeChange(childParentData.id, child.size);

      child = childParentData.nextSibling;
    }
  }

  @override
  void paint(PaintingContext context, Offset canvasStartOffset) {
    assert(childCount == _ssPositions.length);

    // Clip to bounds before any painting, due to extent cache you may get the point ouside bounds
    context.canvas.save();
    context.canvas.clipRect(canvasStartOffset & size);

    // use the canvas background painter, pass it the canvas and that should handle drawing the background
    _canvasBackground.paint(context.canvas, canvasStartOffset, _gridSpaceOffset, _scale, size);

    // though using ssPositionns here directly worked for me but docs using the parentData
    // to get this info is the convention as child can be reordered ( though this will always
    // change the offset as well so should work for me ) and this is the flutter way of implementation
    // on most other stuff ( single source of truth for paint & hit test etc )
    RenderBox? child = firstChild;
    while (child != null) {
      final _CanvasWidgetParentData childParentData = child.parentData! as _CanvasWidgetParentData;

      context.canvas.save();
      // relying purely on canvas manips here
      final drawAt = canvasStartOffset + childParentData.offset;
      context.canvas.translate(drawAt.dx, drawAt.dy);
      context.canvas.scale(childParentData.scale, childParentData.scale);
      context.paintChild(child, Offset.zero); // paint at 0 as already translated

      context.canvas.restore();
      child = childParentData.nextSibling;
    }

    context.canvas.restore(); // clip restore
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    RenderBox? child = lastChild;
    while (child != null) {
      // need to get a coordinate in child space
      final childParentData = child.parentData as _CanvasWidgetParentData;
      final Offset childSpacePosition =
          (position - childParentData.offset /* <- distance in screen space */ ) / childParentData.scale;
      // divide by scale so if screen space is 2x, it's only x in child space
      if (child.hitTest(result, position: childSpacePosition)) {
        return true;
      }
      child = childParentData.previousSibling;
    }
    return false;
  }
}
