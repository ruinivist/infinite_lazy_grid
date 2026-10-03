import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart'; // HardwareKeyboard, LogicalKeyboardKey
import 'package:flutter/gestures.dart'; // PointerScrollEvent
import '../utils/styles.dart';
import 'background.dart';
import 'controller/controller.dart';

/// Determines whether a touch drag navigates or remains available to app tools.
enum TouchNavigationMode { oneFinger, twoFinger }

/// An infinite canvas that places all the children at the specified positions.
/// Needs a [LazyCanvasController] to control the canvas and a [CanvasBackground] to draw the background.
class LazyCanvas extends StatefulWidget {
  final LazyCanvasController controller;
  final int mousePanButtons;

  /// Selects touch navigation for the next sequence; defaults to one finger.
  final TouchNavigationMode touchNavigationMode;

  /// Reports two-finger ownership before raw down delivery or canvas movement.
  /// Remains true until all touches release, even after navigation freezes.
  /// Consumers must cancel their tool operation and suppress further tool input;
  /// raw events and child gestures are not automatically canceled.
  final ValueChanged<bool>? onTouchNavigationChanged;

  /// Composes the viewport and app overlays inside the canvas gesture region.
  /// Keep the supplied viewport at the region's origin and original size.
  final Widget Function(BuildContext context, Widget viewport)? viewportBuilder;
  final void Function(LazyCanvasController controller, Offset delta)?
  onPointerScroll;

  const LazyCanvas({
    required this.controller,
    this.mousePanButtons = kPrimaryMouseButton,
    this.touchNavigationMode = TouchNavigationMode.oneFinger,
    this.onTouchNavigationChanged,
    this.viewportBuilder,
    this.onPointerScroll,
    super.key,
  });

  @override
  State<LazyCanvas> createState() => _LazyCanvasState();
}

class _LazyCanvasState extends State<LazyCanvas>
    with TickerProviderStateMixin<LazyCanvas> {
  final _touches = <int, Offset>{};
  TouchNavigationMode? _touchMode;
  bool _touchNavigationActive = false;
  bool _touchNavigationDraining = false;
  Offset _touchFocalPoint = Offset.zero;
  double _touchInitialSpan = 0;

  TouchNavigationMode get _effectiveTouchMode =>
      _touchMode ?? widget.touchNavigationMode;

  @override
  void initState() {
    super.initState();
    widget.controller.setTickerProvider(this);
  }

  @override
  void didUpdateWidget(covariant LazyCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      // A replacement controller must not inherit an unfinished transform.
      _touchNavigationDraining = _touchNavigationActive;
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
    return Listener(
      behavior: HitTestBehavior
          .translucent, // ensure scroll signals are captured even on empty space
      onPointerSignal: (event) {
        if (event is PointerScaleEvent) {
          final delta = (event.scale - 1) * 0.25; // sensitivity
          widget.controller.updateScalebyDelta(
            delta,
            focalPoint: event.localPosition,
          );
        } else if (event is PointerScrollEvent) {
          final pressed = HardwareKeyboard.instance.logicalKeysPressed;
          if (pressed.contains(LogicalKeyboardKey.controlLeft) ||
              pressed.contains(LogicalKeyboardKey.controlRight)) {
            final delta = (-event.scrollDelta.dy) * 0.0015; // sensitivity
            if (delta != 0) {
              widget.controller.updateScalebyDelta(
                delta,
                focalPoint: event.localPosition,
              );
            }
          } else if (event.scrollDelta.dy != 0) {
            GestureBinding.instance.pointerSignalResolver.register(event, (
              event,
            ) {
              final delta = Offset(
                0,
                (event as PointerScrollEvent).scrollDelta.dy,
              );
              final handler = widget.onPointerScroll;
              if (handler == null) {
                widget.controller.scrollBy(delta);
              } else {
                handler(widget.controller, delta);
              }
            });
          }
        }
        // handle any other registered signal events
        widget.controller.rawPointerSignalListener?.call(event);
      },
      onPointerDown: (event) {
        _handleTouch(event);
        widget.controller.rawPointerDownListener?.call(event);
      },
      onPointerMove: (event) {
        _handleTouch(event);
        widget.controller.rawPointerMoveListener?.call(event);
      },
      onPointerUp: (event) {
        _handleTouch(event);
        widget.controller.rawPointerUpListener?.call(event);
      },
      onPointerCancel: (event) {
        _handleTouch(event);
        widget.controller.rawPointerCancelListener?.call(event);
      },
      child: RawGestureDetector(
        behavior: HitTestBehavior.translucent,
        gestures: {
          _NonMouseScaleGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<
                _NonMouseScaleGestureRecognizer
              >(_NonMouseScaleGestureRecognizer.new, (recognizer) {
                recognizer.touchNavigationMode = () => _effectiveTouchMode;
                _configureScaleRecognizer(recognizer);
              }),
          _MouseScaleGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<
                _MouseScaleGestureRecognizer
              >(_MouseScaleGestureRecognizer.new, (recognizer) {
                recognizer.mousePanButtons = widget.mousePanButtons;
                _configureScaleRecognizer(recognizer);
              }),
        },
        child: ListenableBuilder(
          listenable: widget.controller,
          builder: (context, _) {
            final childrenWithPositions = widget.controller
                .widgetsWithScreenPositions();
            final children = childrenWithPositions.map((e) => e.child).toList();
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
        ),
      ),
    );
  }

  void _configureScaleRecognizer(ScaleGestureRecognizer recognizer) {
    recognizer
      ..onStart = widget.controller.onScaleStart
      ..onUpdate = widget.controller.onScaleUpdate
      ..onEnd = widget.controller.onScaleEnd;
  }

  /// Coordinates raw touches independently of a child's gesture-arena result.
  /// Only the opt-in two-finger mode transforms the canvas here.
  void _handleTouch(PointerEvent event) {
    if (event.kind != PointerDeviceKind.touch) return;
    final configurationChanged = event is! PointerMoveEvent;
    if (event is PointerDownEvent) {
      if (_touches.isEmpty) {
        _touchMode = widget.touchNavigationMode;
        widget.controller.stopAnimation();
      }
      _touches[event.pointer] = event.localPosition;
    } else {
      if (!_touches.containsKey(event.pointer)) return;
      if (event is PointerMoveEvent) {
        _touches[event.pointer] = event.localPosition;
      } else {
        _touches.remove(event.pointer);
      }
    }

    if (_touches.isEmpty) {
      _touchMode = null;
      _touchNavigationDraining = false;
      if (_touchNavigationActive) {
        _touchNavigationActive = false;
        widget.onTouchNavigationChanged?.call(false);
      }
      return;
    }
    if (_effectiveTouchMode != TouchNavigationMode.twoFinger ||
        _touchNavigationDraining) {
      return;
    }
    if (_touches.length < 2) {
      _touchNavigationDraining = _touchNavigationActive;
      return;
    }

    final focalPoint =
        _touches.values.reduce((a, b) => a + b) / _touches.length.toDouble();
    final span =
        _touches.values
            .map((position) => (position - focalPoint).distance)
            .reduce((a, b) => a + b) /
        _touches.length;
    if (configurationChanged || _touchInitialSpan == 0) {
      if (!_touchNavigationActive) {
        _touchNavigationActive = true;
        widget.onTouchNavigationChanged?.call(true);
      }
      _touchFocalPoint = focalPoint;
      _touchInitialSpan = span;
      widget.controller.onScaleStart(
        ScaleStartDetails(
          focalPoint: focalPoint,
          pointerCount: _touches.length,
          kind: PointerDeviceKind.touch,
        ),
      );
      return;
    }

    // Coincident fingers cannot establish a usable zoom ratio.
    if (span == 0) {
      _touchInitialSpan = 0;
      return;
    }
    widget.controller.onScaleUpdate(
      ScaleUpdateDetails(
        focalPoint: focalPoint,
        focalPointDelta: focalPoint - _touchFocalPoint,
        scale: span / _touchInitialSpan,
        pointerCount: _touches.length,
      ),
    );
    _touchFocalPoint = focalPoint;
  }
}

class _NonMouseScaleGestureRecognizer extends ScaleGestureRecognizer {
  late TouchNavigationMode Function() touchNavigationMode;

  @override
  bool isPointerAllowed(PointerDownEvent event) =>
      event.kind != PointerDeviceKind.mouse &&
      event.kind != PointerDeviceKind.stylus &&
      event.kind != PointerDeviceKind.invertedStylus &&
      (event.kind != PointerDeviceKind.touch ||
          touchNavigationMode() == TouchNavigationMode.oneFinger) &&
      super.isPointerAllowed(event);
}

class _MouseScaleGestureRecognizer extends ScaleGestureRecognizer {
  int mousePanButtons = kPrimaryMouseButton;

  @override
  bool isPointerPanZoomAllowed(PointerPanZoomStartEvent event) => false;

  @override
  bool isPointerAllowed(PointerDownEvent event) =>
      event.kind == PointerDeviceKind.mouse &&
      event.buttons & mousePanButtons != 0 &&
      super.isPointerAllowed(event);
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
      child.layout(constraints.loosen(), parentUsesSize: true);

      // notify the controller about the size of the child
      onChildSizeChange(childParentData.id, child.size);

      child = childParentData.nextSibling;
    }
  }

  @override
  void paint(PaintingContext context, Offset canvasStartOffset) {
    assert(childCount == _childInfos.length);

    // Clip to bounds before any painting, due to extent cache you may get the point ouside bounds
    context.canvas.save();
    context.canvas.clipRect(canvasStartOffset & size);

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

      final drawAt = canvasStartOffset + childParentData.offset;

      // Apply transformation using pushTransform for proper coordinate handling
      final transform = Matrix4.identity()
        ..translateByDouble(drawAt.dx, drawAt.dy, 0.0, 1.0)
        ..scaleByDouble(_scale, _scale, 1.0, 1.0);

      // Note: initially I was using context.canvas.translate and context.canvas.scale
      // but that doesn't work with say using a SingleChildScrollView inside a child
      // so using pushTransform is the way to go here

      // 0 offset since transform will take care of it
      context.pushTransform(needsCompositing, Offset.zero, transform, (
        context,
        offset,
      ) {
        context.paintChild(child!, Offset.zero);
      });

      child = childParentData.nextSibling;
    }

    context.canvas.restore(); // clip restore
  }

  @override
  void applyPaintTransform(RenderObject child, Matrix4 transform) {
    final childParentData = child.parentData! as _CanvasWidgetParentData;
    transform
      ..translateByDouble(
        childParentData.offset.dx,
        childParentData.offset.dy,
        0.0,
        1.0,
      )
      ..scaleByDouble(_scale, _scale, 1.0, 1.0);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    RenderBox? child = lastChild;
    while (child != null) {
      final _CanvasWidgetParentData childParentData =
          child.parentData! as _CanvasWidgetParentData;

      bool isHit;
      if (_scale == 1.0) {
        // Fast path: only translated, no scale
        isHit = result.addWithPaintOffset(
          offset: childParentData.offset,
          position: position,
          hitTest: (BoxHitTestResult result, Offset transformed) {
            return child!.hitTest(result, position: transformed);
          },
        );
      } else {
        // same paint transform for hit testing when scaled
        final Matrix4 transform = Matrix4.identity()
          ..translateByDouble(
            childParentData.offset.dx,
            childParentData.offset.dy,
            0.0,
            1.0,
          )
          ..scaleByDouble(_scale, _scale, 1.0, 1.0);

        isHit = result.addWithPaintTransform(
          transform: transform,
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
