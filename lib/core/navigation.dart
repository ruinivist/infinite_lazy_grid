part of 'render.dart';

class _CanvasNavigation extends StatelessWidget {
  const _CanvasNavigation({
    required this.controller,
    required this.mousePanButtons,
    required this.onPointerScroll,
    required this.child,
  });

  final LazyCanvasController controller;
  final int mousePanButtons;
  final void Function(LazyCanvasController, Offset)? onPointerScroll;
  final Widget child;

  void _configure(_DeviceNavigationRecognizer recognizer) {
    recognizer
      ..onStart = (details) {
        recognizer.canceled = false;
        controller.onScaleStart(details);
      }
      ..onUpdate = controller.onScaleUpdate
      ..onEnd = (details) => controller.onScaleEnd(
        recognizer.canceled ? ScaleEndDetails() : details,
      );
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (_) => controller.stopAnimation(),
    onPointerSignal: (event) {
      if (event is! PointerScrollEvent && event is! PointerScaleEvent) return;
      final pressed = HardwareKeyboard.instance.logicalKeysPressed;
      final zoom =
          pressed.contains(LogicalKeyboardKey.controlLeft) ||
          pressed.contains(LogicalKeyboardKey.controlRight);
      GestureBinding.instance.pointerSignalResolver.register(event, (event) {
        if (event is PointerScaleEvent) {
          controller.updateScalebyDelta(
            (event.scale - 1) * 0.25,
            focalPoint: event.localPosition,
          );
        } else if (event is PointerScrollEvent) {
          if (zoom) {
            controller.updateScalebyDelta(
              -event.scrollDelta.dy * 0.0015,
              focalPoint: event.localPosition,
            );
          } else if (onPointerScroll case final handler?) {
            handler(controller, event.scrollDelta);
          } else {
            controller.scrollBy(event.scrollDelta);
          }
        }
      });
    },
    child: RawGestureDetector(
      key: ObjectKey(controller),
      behavior: HitTestBehavior.translucent,
      gestures: {
        _TouchNavigationRecognizer:
            GestureRecognizerFactoryWithHandlers<_TouchNavigationRecognizer>(
              () => _TouchNavigationRecognizer(controller),
              (recognizer) {
                recognizer.gestureSettings = MediaQuery.maybeGestureSettingsOf(
                  context,
                );
              },
            ),
        _MouseNavigationRecognizer:
            GestureRecognizerFactoryWithHandlers<_MouseNavigationRecognizer>(
              _MouseNavigationRecognizer.new,
              (recognizer) {
                recognizer.mousePanButtons = mousePanButtons;
                _configure(recognizer);
              },
            ),
        _TrackpadNavigationRecognizer:
            GestureRecognizerFactoryWithHandlers<_TrackpadNavigationRecognizer>(
              _TrackpadNavigationRecognizer.new,
              _configure,
            ),
      },
      child: child,
    ),
  );
}

class _DeviceNavigationRecognizer extends ScaleGestureRecognizer {
  bool canceled = false;

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerCancelEvent) canceled = true;
    super.handleEvent(event);
  }
}

class _MouseNavigationRecognizer extends _DeviceNavigationRecognizer {
  int mousePanButtons = kPrimaryMouseButton;

  @override
  bool isPointerPanZoomAllowed(PointerPanZoomStartEvent event) => false;

  @override
  bool isPointerAllowed(PointerDownEvent event) =>
      event.kind == PointerDeviceKind.mouse &&
      event.buttons & mousePanButtons != 0 &&
      super.isPointerAllowed(event);
}

class _TrackpadNavigationRecognizer extends _DeviceNavigationRecognizer {
  @override
  bool isPointerAllowed(PointerDownEvent event) => false;
}

Offset _touchCenter(Iterable<Offset> positions) =>
    positions.reduce((a, b) => a + b) / positions.length.toDouble();

double _touchSpan(Iterable<Offset> positions, Offset center) =>
    positions.map((p) => (p - center).distance).reduce((a, b) => a + b) /
    positions.length;

class _NavigationSample {
  _NavigationSample(this.positions, this.time, this.changed);
  Map<int, Offset> positions;
  Duration time;
  final Set<int> changed;
  bool waited = false;
}

/// Uses the gesture arena for ownership and coordinated samples for motion.
class _TouchNavigationRecognizer extends OneSequenceGestureRecognizer {
  _TouchNavigationRecognizer(this.controller)
    : super(supportedDevices: {PointerDeviceKind.touch});

  final LazyCanvasController controller;
  final _contacts = <int, Offset>{};
  final _won = <int>{};
  final _samples = <_NavigationSample>[];
  final _pendingChanged = <int>{};
  int? _frame;
  bool _recognized = false;
  bool _started = false;
  bool _scaled = false;
  bool _canceled = false;
  Offset _initialCenter = Offset.zero;
  Offset _appliedCenter = Offset.zero;
  double _initialSpan = 0;
  double _baseScale = 1;
  Duration _time = Duration.zero;
  Offset _velocityPosition = Offset.zero;
  VelocityTracker _velocity = VelocityTracker.withKind(PointerDeviceKind.touch);

  @override
  String get debugDescription => 'canvas navigation';

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (!event.localPosition.isFinite) return;
    _flush();
    if (_contacts.isEmpty) {
      _velocityPosition = Offset.zero;
      _velocity = VelocityTracker.withKind(PointerDeviceKind.touch);
    }
    startTrackingPointer(event.pointer, event.transform);
    _contacts[event.pointer] = event.localPosition;
    _time = event.timeStamp;
    _rebase();
    if (_recognized) resolve(GestureDisposition.accepted);
  }

  void _rebase() {
    _initialCenter = _appliedCenter = _touchCenter(_contacts.values);
    _initialSpan = _touchSpan(_contacts.values, _initialCenter);
    _baseScale = controller.scale;
    _pendingChanged.clear();
    _velocity.addPosition(_time, _velocityPosition);
    if (_started) controller.onScaleStart(ScaleStartDetails());
  }

  @override
  void handleEvent(PointerEvent event) {
    if (!_contacts.containsKey(event.pointer)) return;
    _time = event.timeStamp;
    if (event is PointerMoveEvent) {
      if (!event.localPosition.isFinite ||
          event.localPosition == _contacts[event.pointer]) {
        return;
      }
      _contacts[event.pointer] = event.localPosition;
      if (!_started) {
        _pendingChanged.add(event.pointer);
        final center = _touchCenter(_contacts.values);
        final span = _touchSpan(_contacts.values, center);
        if ((center - _initialCenter).distance >
                computePanSlop(event.kind, gestureSettings) ||
            (span - _initialSpan).abs() > computeScaleSlop(event.kind)) {
          _recognized = true;
          resolve(GestureDisposition.accepted);
          _tryStart();
        }
      } else {
        final previous = _samples.lastOrNull;
        if (previous != null && !previous.changed.contains(event.pointer)) {
          previous
            ..positions = Map.of(_contacts)
            ..time = _time;
          previous.changed.add(event.pointer);
        } else {
          _samples.add(
            _NavigationSample(Map.of(_contacts), _time, {event.pointer}),
          );
        }
        _scheduleFrame();
      }
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      _canceled |= event is PointerCancelEvent;
      _remove(event.pointer);
      stopTrackingPointer(event.pointer);
    }
  }

  void _tryStart() {
    if (_started || !_recognized || _won.isEmpty) return;
    _started = true;
    controller.onScaleStart(ScaleStartDetails());
    _samples.add(
      _NavigationSample(Map.of(_contacts), _time, Set.of(_pendingChanged)),
    );
    _scheduleFrame();
  }

  @override
  void acceptGesture(int pointer) {
    _won.add(pointer);
    _tryStart();
  }

  @override
  void rejectGesture(int pointer) {
    _canceled = true;
    _remove(pointer);
    stopTrackingPointer(pointer);
  }

  void _remove(int pointer) {
    if (!_contacts.containsKey(pointer)) return;
    _flush();
    _contacts.remove(pointer);
    _won.remove(pointer);
    if (_contacts.isNotEmpty) {
      _rebase();
    } else {
      if (_started) {
        _velocity.addPosition(_time, _velocityPosition);
        final velocity = _scaled || _canceled
            ? Velocity.zero
            : _velocity.getVelocity().clampMagnitude(0, kMaxFlingVelocity);
        controller.onScaleEnd(ScaleEndDetails(velocity: velocity));
      }
      _started = _recognized = _scaled = _canceled = false;
      _pendingChanged.clear();
    }
  }

  void _scheduleFrame() {
    _frame ??= SchedulerBinding.instance.scheduleFrameCallback((_) {
      _frame = null;
      var ready = -1;
      for (var i = 0; i < _samples.length; i++) {
        final sample = _samples[i];
        // A partial pan can look like a pinch. Its deadline never renews.
        if (sample.waited || sample.changed.length == _contacts.length) {
          ready = i;
        }
        sample.waited = true;
      }
      if (ready >= 0) {
        final sample = _samples[ready];
        _samples.removeRange(0, ready + 1);
        _apply(sample);
      }
      if (_samples.isNotEmpty) _scheduleFrame();
    });
  }

  void _apply(_NavigationSample sample) {
    final center = _touchCenter(sample.positions.values);
    final span = _touchSpan(sample.positions.values, center);
    if (!span.isFinite || !center.isFinite) return;
    final hasBaseline = _initialSpan > 0;
    var ratio = hasBaseline ? span / _initialSpan : 1.0;
    if (!ratio.isFinite || (ratio == 0 && controller.minScale == null)) {
      ratio = controller.scale / _baseScale;
    }
    _scaled |= ratio != 1;
    controller.onScaleUpdate(
      ScaleUpdateDetails(
        focalPoint: center,
        localFocalPoint: center,
        focalPointDelta: center - _appliedCenter,
        scale: ratio,
        pointerCount: sample.positions.length,
      ),
    );
    _velocityPosition += center - _appliedCenter;
    _appliedCenter = center;
    _velocity.addPosition(sample.time, _velocityPosition);
    if (!hasBaseline && span > 0) {
      _initialSpan = span;
      _baseScale = controller.scale;
      controller.onScaleStart(ScaleStartDetails());
    }
  }

  void _flush() {
    if (_samples.isNotEmpty) _apply(_samples.last);
    _cancelFrame();
  }

  void _cancelFrame() {
    if (_frame case final id?) {
      SchedulerBinding.instance.cancelFrameCallbackWithId(id);
    }
    _frame = null;
    _samples.clear();
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    resolve(GestureDisposition.rejected);
  }

  @override
  void dispose() {
    _cancelFrame();
    super.dispose();
  }
}
