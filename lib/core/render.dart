import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import '../utils/styles.dart';
import '../utils/conversions.dart';
import 'background.dart';
import 'controller/controller.dart';

part 'debug.dart';
part 'navigation.dart';

/// An infinite canvas that lazily lays out children in canvas coordinates.
class LazyCanvas extends StatefulWidget {
  final LazyCanvasController controller;

  /// Mouse buttons that pan with the default navigation wrapper.
  final int mousePanButtons;

  /// Temporarily paints and targets this child above the document stack.
  /// Does not change controller order or remount keyed child state.
  final CanvasChildId? foregroundChildId;

  /// Composes the viewport and overlays inside the navigation region.
  /// Keep the viewport at the region's origin and original size.
  final Widget Function(BuildContext context, Widget viewport)? viewportBuilder;

  /// Replaces all default touch, mouse, trackpad, and wheel navigation.
  /// Return the child unchanged to disable built-in navigation. It includes
  /// [viewportBuilder] content. Raw controller pointer callbacks still observe
  /// input. Custom wrappers own recognition, cancellation, and pointer signals;
  /// [mousePanButtons] and [onPointerScroll] only configure the default wrapper.
  final Widget Function(BuildContext context, Widget child)? navigationBuilder;

  /// Replaces ordinary wheel scrolling in the default navigation wrapper.
  final void Function(LazyCanvasController controller, Offset delta)?
  onPointerScroll;

  const LazyCanvas({
    required this.controller,
    this.mousePanButtons = kPrimaryMouseButton,
    this.foregroundChildId,
    this.viewportBuilder,
    this.navigationBuilder,
    this.onPointerScroll,
    super.key,
  });

  @override
  State<LazyCanvas> createState() => _LazyCanvasState();
}

class _LazyCanvasState extends State<LazyCanvas>
    with TickerProviderStateMixin<LazyCanvas> {
  @override
  void initState() {
    super.initState();
    widget.controller.setTickerProvider(this);
  }

  @override
  void didUpdateWidget(covariant LazyCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.setTickerProvider(null);
      widget.controller.setTickerProvider(this);
    }
  }

  @override
  void dispose() {
    widget.controller.setTickerProvider(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    widget.controller.setBuildContext(context);
    final viewport = ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final childrenWithPositions = List<ChildInfo>.of(
          widget.controller.widgetsWithScreenPositions(),
        );
        final foregroundIndex = childrenWithPositions.indexWhere(
          (info) => info.id == widget.foregroundChildId,
        );
        if (foregroundIndex >= 0) {
          childrenWithPositions.add(
            childrenWithPositions.removeAt(foregroundIndex),
          );
        }
        final children = childrenWithPositions.map((info) {
          Widget child = info.child;
          if (widget.controller.debug) {
            child = _Debug(
              id: info.id,
              gs: info.gsPosition,
              ss: info.ssPosition,
              child: child,
            );
          }
          return Container(key: ValueKey<String>(info.id), child: child);
        }).toList();
        Widget viewport = _CanvasRenderObject(
          childInfos: childrenWithPositions,
          canvasBackground: widget.controller.background,
          scale: widget.controller.scale,
          gridSpaceOffset: widget.controller.offset,
          onCanvasSizeChange: widget.controller.onCanvasSizeChange,
          onChildSizeChange: widget.controller.onChildSizeChange,
          children: children,
        );

        if (widget.controller.debug) {
          viewport = Stack(
            children: [
              viewport,
              Positioned(
                top: 16,
                left: 16,
                child: Text(
                  'Offset: (${widget.controller.offset.dx.toStringAsFixed(2)}, '
                  '${widget.controller.offset.dy.toStringAsFixed(2)})\n'
                  'Scale: ${widget.controller.scale.toStringAsFixed(1)}',
                  style: monospaceStyle(context),
                ),
              ),
            ],
          );
        }
        return widget.viewportBuilder?.call(context, viewport) ?? viewport;
      },
    );
    final navigation =
        widget.navigationBuilder?.call(context, viewport) ??
        _CanvasNavigation(
          controller: widget.controller,
          mousePanButtons: widget.mousePanButtons,
          onPointerScroll: widget.onPointerScroll,
          child: viewport,
        );
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) =>
          widget.controller.rawPointerDownListener?.call(event),
      onPointerMove: (event) =>
          widget.controller.rawPointerMoveListener?.call(event),
      onPointerUp: (event) =>
          widget.controller.rawPointerUpListener?.call(event),
      onPointerCancel: (event) =>
          widget.controller.rawPointerCancelListener?.call(event),
      onPointerSignal: (event) =>
          widget.controller.rawPointerSignalListener?.call(event),
      child: navigation,
    );
  }
}

/// A combined widget for all the render object of the children + background.
/// Everything is in screen space here
class _CanvasRenderObject extends MultiChildRenderObjectWidget {
  final List<ChildInfo> childInfos;
  final double scale;
  final Offset gridSpaceOffset;
  final CanvasBackground canvasBackground;
  final Function onCanvasSizeChange;
  final Function onChildSizeChange;

  const _CanvasRenderObject({
    required this.childInfos,
    required this.scale,
    required this.gridSpaceOffset,
    required this.canvasBackground,
    required this.onCanvasSizeChange,
    required this.onChildSizeChange,
    required super.children, // children go to the MultiChildRenderObjectWidget
  }) : assert(
         childInfos.length == children.length,
         'Children and information must have the same length',
       ),
       assert(scale != 0);

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _CanvasRenderBox(
      childInfos: childInfos,
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
      ..childInfos = childInfos
      ..canvasBackground = canvasBackground
      ..gridSpaceOffset = gridSpaceOffset
      ..scale = scale
      ..onCanvasSizeChange = onCanvasSizeChange
      ..onChildSizeChange = onChildSizeChange;
  }
}

class _CanvasWidgetParentData extends ContainerBoxParentData<RenderBox> {
  // there is already an "offset" defined in BoxParentdata that is exactly what I want
  late CanvasChildId id;
  double rotation = 0;
}

class _CanvasRenderBox extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _CanvasWidgetParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _CanvasWidgetParentData> {
  CanvasBackground _canvasBackground;
  List<ChildInfo> _childInfos;
  Offset _gridSpaceOffset;
  double _scale;
  Function onCanvasSizeChange;
  Function onChildSizeChange;

  _CanvasRenderBox({
    required List<ChildInfo> childInfos,
    required double scale,
    required Offset gridSpaceOffset,
    required CanvasBackground canvasBackground,
    required this.onCanvasSizeChange,
    required this.onChildSizeChange,
  }) : _childInfos = childInfos,
       _scale = scale,
       _gridSpaceOffset = gridSpaceOffset,
       _canvasBackground = canvasBackground;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _CanvasWidgetParentData) {
      child.parentData = _CanvasWidgetParentData();
    }
  }

  set childInfos(List<ChildInfo> childInfos) {
    // Child count is checked during layout, after the widget updates finish.
    if (_childInfos != childInfos) {
      _childInfos = childInfos;
      markNeedsLayout();
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
    if (!identical(_canvasBackground, canvasBackground)) {
      if (attached) {
        _canvasBackground.repaint?.removeListener(_handleBackgroundRepaint);
      }
      _canvasBackground = canvasBackground;
      if (attached) {
        _canvasBackground.repaint?.addListener(_handleBackgroundRepaint);
      }
      markNeedsPaint();
    }
  }

  void _handleBackgroundRepaint() => markNeedsPaint();

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _canvasBackground.repaint?.addListener(_handleBackgroundRepaint);
  }

  @override
  void detach() {
    _canvasBackground.repaint?.removeListener(_handleBackgroundRepaint);
    super.detach();
  }

  @override
  void performLayout() {
    assert(childCount == _childInfos.length);
    size = constraints.biggest; // expand as much as possible for the parent
    onCanvasSizeChange(size); // notify the controller about the size

    RenderBox? child = firstChild;

    int index = 0;
    while (child != null) {
      final _CanvasWidgetParentData childParentData =
          child.parentData! as _CanvasWidgetParentData;
      final info = _childInfos[index++];
      childParentData.offset = info.ssPosition;
      childParentData.id = info.id;
      childParentData.rotation = info.rotation;
      child.layout(constraints.loosen(), parentUsesSize: true);

      // notify the controller about the size of the child
      onChildSizeChange(childParentData.id, child.size);

      child = childParentData.nextSibling;
    }
  }

  @override
  void paint(PaintingContext context, Offset canvasStartOffset) {
    assert(childCount == _childInfos.length);

    // Clip composited child layers too, so they cannot paint outside the canvas viewport.
    context.pushClipRect(needsCompositing, canvasStartOffset, Offset.zero & size, (
      context,
      _,
    ) {
      // use the canvas background painter, pass it the canvas and that should handle drawing the background
      _canvasBackground.paint(
        context.canvas,
        canvasStartOffset,
        _gridSpaceOffset,
        _scale,
        size,
      );

      // though using ssPositionns here directly worked for me but docs using the parentData
      // to get this info is the convention as child can be reordered ( though this will always
      // change the offset as well so should work for me ) and this is the flutter way of implementation
      // on most other stuff ( single source of truth for paint & hit test etc )
      RenderBox? child = firstChild;
      while (child != null) {
        final _CanvasWidgetParentData childParentData =
            child.parentData! as _CanvasWidgetParentData;

        // Apply transformation using pushTransform for proper coordinate handling
        final transform = _transformFor(child);

        // Note: initially I was using context.canvas.translate and context.canvas.scale
        // but that doesn't work with say using a SingleChildScrollView inside a child
        // so using pushTransform is the way to go here

        // PaintingContext applies the canvas offset around the child transform.
        context.pushTransform(needsCompositing, canvasStartOffset, transform, (
          context,
          offset,
        ) {
          context.paintChild(child!, offset);
        });

        child = childParentData.nextSibling;
      }
    });
  }

  Matrix4 _transformFor(RenderBox child) {
    final data = child.parentData! as _CanvasWidgetParentData;
    return childTransform(
      data.offset,
      child.size,
      data.rotation,
      scale: _scale,
    );
  }

  @override
  void applyPaintTransform(RenderObject child, Matrix4 transform) {
    transform.multiply(_transformFor(child as RenderBox));
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    RenderBox? child = lastChild;
    while (child != null) {
      final _CanvasWidgetParentData childParentData =
          child.parentData! as _CanvasWidgetParentData;

      bool isHit;
      if (_scale == 1.0 && childParentData.rotation == 0) {
        // Fast path: only translated, no scale or rotation
        isHit = result.addWithPaintOffset(
          offset: childParentData.offset,
          position: position,
          hitTest: (BoxHitTestResult result, Offset transformed) {
            return child!.hitTest(result, position: transformed);
          },
        );
      } else {
        // same paint transform for hit testing when scaled or rotated
        isHit = result.addWithPaintTransform(
          transform: _transformFor(child),
          position: position,
          hitTest: (BoxHitTestResult result, Offset transformed) {
            return child!.hitTest(result, position: transformed);
          },
        );
      }

      if (isHit) {
        return true;
      }

      child = childParentData.previousSibling;
    }
    return false;
  }
}
