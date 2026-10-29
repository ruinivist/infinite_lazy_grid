// Verifies stable rendered two-finger motion with independent input and display clocks.
// Exercises LazyCanvas navigation without an application editor.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_lazy_grid/infinite_lazy_grid.dart';

import 'touch_test_helpers.dart';

// ---------- Acceptance tests ----------

void main() {
  const initial = (Offset(250, 340), Offset(490, 340));
  const start = (offset: Offset.zero, scale: 1.0);
  const previous = (Offset(260, 340), Offset(500, 340));
  const target = (Offset(270, 340), Offset(510, 340));
  test('frame checks accept interpolation along the stable pan path', () {
    final report = TouchMotionReport();
    for (final x in [10.0, 15.0, 20.0]) {
      final actual = (offset: Offset(-x, 0), scale: 1.0);
      final expected = permittedTouchView((
        lower: expectedTouchView(start, initial, previous),
        upper: expectedTouchView(start, initial, target),
      ), screenTouchPoints(actual));
      report.sample(
        Duration.zero,
        screenTouchPoints(actual),
        expected,
        'coherent pan at $x',
      );
    }
    report.verify();
  });

  test(
    'identical received prefixes hold the same stable view and reject the raw zoom pulse',
    () {
      final reports = <TouchBounds>[];
      for (final motion in [_Motion.pan, _Motion.stationaryFinger]) {
        final samples = _TouchSamples(
          start,
          initial,
          motion: motion,
        )..move(Duration.zero, 1, initial.$2 + const Offset(20, 10), sample: 1);
        final bounds = samples.frame(const Duration(milliseconds: 2));
        reports.add(bounds);
        expect(bounds, (lower: start, upper: start));
        final pulse = expectedTouchView(start, initial, samples.arrived);
        final report = TouchMotionReport()
          ..sample(
            Duration.zero,
            screenTouchPoints(pulse),
            permittedTouchView(bounds, screenTouchPoints(pulse)),
            'raw half-update pulse',
          );
        expect(report.verify, throwsA(isA<TestFailure>()));
      }
      expect(reports[0], reports[1]);
    },
  );

  for (final hz in [60, 120]) {
    for (final phase in [2, 5, 6]) {
      test(
        'one extra frame passes, a second extra frame fails at $hz Hz / ${phase}ms phase',
        () {
          final samples = _TouchSamples(start, initial)
            ..move(Duration.zero, 0, target.$1, sample: 1)
            ..move(Duration.zero, 1, target.$2, sample: 1, last: true);
          final first = Duration(milliseconds: phase);
          final second = first + Duration(microseconds: (1000000 / hz).round());
          final intended = expectedTouchView(start, initial, target);
          final firstBounds = samples.frame(first);
          final secondBounds = samples.frame(second);
          TouchMotionReport()
            ..sample(
              first,
              screenTouchPoints(start),
              permittedTouchView(firstBounds, screenTouchPoints(start)),
              'one frame hold',
            )
            ..sample(
              second,
              screenTouchPoints(intended),
              permittedTouchView(secondBounds, screenTouchPoints(intended)),
              'response',
            )
            ..verify();
          final stalled = TouchMotionReport()
            ..sample(
              second,
              screenTouchPoints(start),
              permittedTouchView(secondBounds, screenTouchPoints(start)),
              'excess delay',
            );
          expect(stalled.verify, throwsA(isA<TestFailure>()));
        },
      );
    }
  }

  test('new input cannot renew an older response deadline', () {
    final samples = _TouchSamples(start, initial)
      ..move(Duration.zero, 0, previous.$1, sample: 1)
      ..move(Duration.zero, 1, previous.$2, sample: 1, last: true)
      ..frame(const Duration(milliseconds: 2))
      ..move(const Duration(milliseconds: 8), 0, target.$1, sample: 2)
      ..move(
        const Duration(milliseconds: 8),
        1,
        target.$2,
        sample: 2,
        last: true,
      );
    final bounds = samples.frame(const Duration(milliseconds: 10));
    final report = TouchMotionReport()
      ..sample(
        Duration.zero,
        screenTouchPoints(start),
        permittedTouchView(bounds, screenTouchPoints(start)),
        'accumulating delay',
      );
    expect(report.verify, throwsA(isA<TestFailure>()));
  });

  test('frame checks reject an incorrect centroid anchor', () {
    final current = (initial.$1, initial.$2 + const Offset(72, 42));
    final correct = expectedTouchView(start, initial, current);
    final wrong = (
      offset: correct.offset + const Offset(12, 8),
      scale: correct.scale,
    );
    final report = TouchMotionReport()
      ..sample(
        Duration.zero,
        screenTouchPoints(wrong),
        correct,
        'centroid drift',
      )
      ..sample(
        const Duration(milliseconds: 16),
        screenTouchPoints(start),
        start,
        'correct endpoint',
      );
    expect(report.verify, throwsA(isA<TestFailure>()));
  });

  test('independent frame schedules observe both sides of trailing input', () {
    for (final timing in [
      (hz: 60, phase: const Duration(milliseconds: 6)),
      (hz: 120, phase: _framePhase),
    ]) {
      final steps = _schedule(
        _Motion.pan,
        _Delivery.staggered,
        inputHz: 60,
        frameHz: timing.hz,
        framePhase: timing.phase,
      );
      final moves = steps.where((step) => step.finger != null).toList();
      final frames = steps.where((step) => step.finger == null).toList();
      expect(
        frames.any(
          (step) => step.time > moves[1].time && step.time < moves[2].time,
        ),
        isTrue,
      );
      if (timing.hz == 120) {
        expect(
          frames.any(
            (step) => step.time > moves[0].time && step.time < moves[1].time,
          ),
          isTrue,
        );
      }
      final samples = _TouchSamples(start, initial);
      final report = TouchMotionReport();
      for (final step in steps) {
        if (step.finger case final finger?) {
          samples.move(
            step.time,
            finger,
            step.position!,
            sample: step.sample!,
            last: step.last,
          );
        } else {
          final bounds = samples.frame(step.time);
          var fake = bounds.lower;
          if (step.time > moves[1].time && step.time < moves[2].time) {
            fake = (
              offset: fake.offset + const Offset(0, 8),
              scale: fake.scale,
            );
          }
          final painted = screenTouchPoints(fake);
          report.sample(
            step.time,
            painted,
            permittedTouchView(bounds, painted),
            'post-trailing corruption',
          );
        }
      }
      expect(report.verify, throwsA(isA<TestFailure>()));
      expect(report.worstTime, greaterThan(moves[1].time));
      expect(report.worstTime, lessThan(moves[2].time));
    }
  });

  for (final lockZoom in [false, true]) {
    test(
      'transition checks reject locked ${lockZoom ? 'zoom' : 'pan'} despite correct endpoints',
      () {
        final report = TouchMotionReport();
        for (var i = 0; i <= 30; i++) {
          final touches = _positions(_Motion.transitions, i / 30);
          final intended = expectedTouchView(start, initial, touches);
          final bad = lockZoom
              ? (offset: intended.offset, scale: start.scale)
              : (offset: start.offset, scale: intended.scale);
          report.sample(
            Duration(milliseconds: i * 17),
            screenTouchPoints(bad),
            intended,
            'locked component',
          );
        }
        expect(report.verify, throwsA(isA<TestFailure>()));
      },
    );
  }

  test(
    'staggered input permits a stable hold then requires the coherent pan',
    () {
      for (final hz in [60, 120]) {
        for (final leading in [0, 1]) {
          final samples = _TouchSamples(start, initial);
          final report = TouchMotionReport();
          final interval = Duration(microseconds: (1000000 / hz).round());
          for (var sample = 1; sample <= 10; sample++) {
            final firstFrame =
                const Duration(milliseconds: 2) + interval * (2 * (sample - 1));
            final delta = Offset(sample * 20.0, 0);
            final touches = (initial.$1 + delta, initial.$2 + delta);
            samples.move(
              firstFrame - const Duration(milliseconds: 2),
              leading,
              leading == 0 ? touches.$1 : touches.$2,
              sample: sample,
            );
            final held = (offset: Offset(-(sample - 1) * 20.0, 0), scale: 1.0);
            report.sample(
              firstFrame,
              screenTouchPoints(held),
              permittedTouchView(
                samples.frame(firstFrame),
                screenTouchPoints(held),
              ),
              'stable hold',
            );
            samples.move(
              firstFrame + const Duration(milliseconds: 2),
              1 - leading,
              leading == 0 ? touches.$2 : touches.$1,
              sample: sample,
              last: true,
            );
            final responded = (offset: -delta, scale: 1.0);
            final secondFrame = firstFrame + interval;
            report.sample(
              secondFrame,
              screenTouchPoints(responded),
              permittedTouchView(
                samples.frame(secondFrame),
                screenTouchPoints(responded),
              ),
              'coherent response',
            );
          }
          report.verify();
        }
      }
    },
  );

  test(
    'continuous one-frame-delayed pan passes without accumulating latency',
    () {
      for (final hz in [60, 120]) {
        final samples = _TouchSamples(start, initial);
        final report = TouchMotionReport();
        for (var frame = 1; frame <= 10; frame++) {
          final time = Duration(microseconds: (frame * 1000000 / hz).round());
          final delta = Offset(frame * 10.0, 0);
          samples
            ..move(time, 0, initial.$1 + delta, sample: frame)
            ..move(time, 1, initial.$2 + delta, sample: frame, last: true);
          final bounds = samples.frame(time);
          final delayed = (offset: Offset(-(frame - 1) * 10.0, 0), scale: 1.0);
          report.sample(
            time,
            screenTouchPoints(delayed),
            permittedTouchView(bounds, screenTouchPoints(delayed)),
            'continuous delayed pan',
          );
        }
        report.verify();
      }
    },
  );

  test('frame checks reject nonfinite rendered positions', () {
    final report = TouchMotionReport();
    expect(
      () => report.sample(
        Duration.zero,
        const [Offset(double.nan, 0), Offset.zero, Offset.zero],
        start,
        'invalid frame',
      ),
      throwsA(isA<TestFailure>()),
    );
  });

  for (final (name, bad) in [
    ('sideways jump', (offset: const Offset(-15, -8), scale: 1.0)),
    ('unwanted zoom', (offset: const Offset(-15, 0), scale: 1.02)),
    ('stalled motion', (offset: Offset.zero, scale: 1.0)),
    ('overshoot', (offset: const Offset(-30, 0), scale: 1.0)),
  ]) {
    test('frame checks fail on $name despite correct endpoints', () {
      final report = TouchMotionReport();
      final before = expectedTouchView(start, initial, previous);
      final after = expectedTouchView(start, initial, target);
      report
        ..sample(Duration.zero, screenTouchPoints(before), before, 'before')
        ..sample(
          const Duration(milliseconds: 8),
          screenTouchPoints(bad),
          permittedTouchView((
            lower: expectedTouchView(start, initial, previous),
            upper: expectedTouchView(start, initial, target),
          ), screenTouchPoints(bad)),
          name,
        )
        ..sample(
          const Duration(milliseconds: 16),
          screenTouchPoints(after),
          after,
          'after',
        );
      expect(report.verify, throwsA(isA<TestFailure>()));
      expect(report.worstTime, const Duration(milliseconds: 8));
    });
  }

  for (final upper in [false, true]) {
    for (final corrupt in [false, true]) {
      testWidgets(
        'zoom-limit frame checks ${corrupt ? 'reject a first-frame jump' : 'accept one stable frame'} at ${upper ? 'maximum' : 'minimum'} zoom',
        (tester) async {
          await pumpTouchCanvas(tester);
          final controller = tester
              .widget<LazyCanvas>(find.byType(LazyCanvas))
              .controller;
          final limit = upper ? controller.maxScale! : controller.minScale!;
          controller.updateScalebyDelta(
            limit - controller.scale,
            focalPoint: Offset.zero,
          );
          await tester.pump();
          final start = touchView(controller);
          const pan = Offset(20, 0);
          final target = (
            offset: start.offset - pan / start.scale,
            scale: start.scale,
          );
          if (corrupt) controller.scrollBy(const Offset(0, 20));
          tester.binding.addPostFrameCallback((_) {
            if (corrupt) controller.scrollBy(const Offset(0, -20));
            controller.scrollBy(-pan);
          });
          tester.binding.scheduleFrame();
          final check = pumpTouchResponse(
            tester,
            previous: start,
            target: target,
          );
          if (corrupt) {
            TestFailure? failure;
            try {
              await check;
            } on TestFailure catch (error) {
              failure = error;
            }
            expect(
              failure,
              isA<TestFailure>().having(
                (failure) => failure.message,
                'message',
                contains('frame 1'),
              ),
            );
          } else {
            await check;
          }
          TouchMotionReport()
            ..sample(
              Duration.zero,
              paintedTouchLandmarks(tester),
              target,
              'correct second frame',
            )
            ..verify();
        },
      );
    }
  }

  testWidgets(
    'two-finger subpixel movement has no dead zone and stays still during a pause',
    (tester) async {
      await pumpTouchCanvas(tester);
      final controller = tester
          .widget<LazyCanvas>(find.byType(LazyCanvas))
          .controller;
      const initial = (Offset(250, 340), Offset(490, 340));
      final start = touchView(controller);
      final first = await startTouchNavigation(tester, initial.$1, pointer: 1);
      final second = await tester.startGesture(initial.$2, pointer: 2);
      var previous = start;
      for (final delta in [
        const Offset(0.25, 0.125),
        const Offset(0.5, 0.25),
        Offset.zero,
      ]) {
        await first.moveTo(initial.$1 + delta);
        await second.moveTo(initial.$2 + delta);
        final target = (
          offset: start.offset - delta / start.scale,
          scale: start.scale,
        );
        await pumpTouchResponse(tester, previous: previous, target: target);
        previous = target;
        final paused = target;
        await pumpTouchHold(tester, expected: paused);
        expectTouchView(
          touchView(controller),
          paused,
          'holding both fingers still must not move the viewport',
        );
      }
      await second.up();
      await first.up();
    },
  );

  for (final upper in [false, true]) {
    testWidgets(
      'pinch at the ${upper ? 'upper' : 'lower'} zoom limit keeps panning and recovers',
      (tester) async {
        await pumpTouchCanvas(tester);
        final controller = tester
            .widget<LazyCanvas>(find.byType(LazyCanvas))
            .controller;
        const center = Offset(380, 340);
        final start = touchView(controller);
        final anchor = start.offset + center / start.scale;
        final first = await startTouchNavigation(
          tester,
          center - const Offset(40, 0),
          pointer: 1,
        );
        final second = await tester.startGesture(
          center + const Offset(40, 0),
          pointer: 2,
        );
        final ratios = upper ? [4.0, 5.0, 4.0, 1.5] : [0.2, 0.1, 0.2, 0.75];
        var previous = start;
        for (var sample = 0; sample < ratios.length; sample++) {
          final movedCenter =
              center + Offset(10.0 * (sample + 1), 5.0 * (sample + 1));
          final radius = Offset(40 * ratios[sample], 0);
          await first.moveTo(movedCenter - radius);
          await second.moveTo(movedCenter + radius);
          final scale = (start.scale * ratios[sample]).clamp(
            controller.minScale!,
            controller.maxScale!,
          );
          final target = (offset: anchor - movedCenter / scale, scale: scale);
          await pumpTouchResponse(tester, previous: previous, target: target);
          previous = target;
          expect(controller.scale, closeTo(scale, touchTolerance));
          expect(
            (projectTouch(touchView(controller), anchor) - movedCenter)
                .distance,
            lessThan(touchTolerance),
            reason:
                'the original canvas anchor must follow the moving centroid even while zoom is clamped',
          );
        }
        await second.up();
        await first.up();
      },
    );
  }

  testWidgets(
    'coincident fingers pan and preserve centroid movement when separating',
    (tester) async {
      await pumpTouchCanvas(tester);
      final controller = tester
          .widget<LazyCanvas>(find.byType(LazyCanvas))
          .controller;
      const center = Offset(380, 340);
      final first = await startTouchNavigation(tester, center, pointer: 1);
      final second = await tester.startGesture(center, pointer: 2);
      final start = touchView(controller);
      const delta = Offset(20, 10);
      await first.moveTo(center + delta);
      await second.moveTo(center + delta);
      final panned = (
        offset: start.offset - delta / start.scale,
        scale: start.scale,
      );
      await pumpTouchResponse(tester, previous: start, target: panned);
      expectTouchView(
        touchView(controller),
        panned,
        'zero separation must not freeze two-finger panning',
      );
      final movedCenter = center + delta;
      await second.moveTo(movedCenter + const Offset(40, 0));
      final separated = (
        offset: panned.offset - const Offset(20, 0) / start.scale,
        scale: start.scale,
      );
      await pumpTouchResponse(tester, previous: panned, target: separated);
      expectTouchView(
        touchView(controller),
        separated,
        'establishing a zoom baseline must preserve centroid movement',
      );
      await second.moveTo(movedCenter + const Offset(60, 0));
      final pinched = expectedTouchView(
        separated,
        (movedCenter, movedCenter + const Offset(40, 0)),
        (movedCenter, movedCenter + const Offset(60, 0)),
      );
      await pumpTouchResponse(tester, previous: separated, target: pinched);
      await second.up();
      await first.up();
    },
  );

  testWidgets(
    'fingers meeting and separating preserve the focal anchor and gesture scale',
    (tester) async {
      await pumpTouchCanvas(tester);
      final controller = tester
          .widget<LazyCanvas>(find.byType(LazyCanvas))
          .controller;
      const center = Offset(380, 340);
      final start = touchView(controller);
      final anchor = start.offset + center / start.scale;
      final first = await startTouchNavigation(
        tester,
        center - const Offset(40, 0),
        pointer: 1,
      );
      final second = await tester.startGesture(
        center + const Offset(40, 0),
        pointer: 2,
      );
      var previous = start;
      for (final radius in [0.0, 10.0, 40.0]) {
        await first.moveTo(center - Offset(radius, 0));
        await second.moveTo(center + Offset(radius, 0));
        final scale = (start.scale * radius / 40).clamp(
          controller.minScale!,
          controller.maxScale!,
        );
        final target = (offset: anchor - center / scale, scale: scale);
        await pumpTouchResponse(tester, previous: previous, target: target);
        previous = target;
        expectTouchView(
          touchView(controller),
          (offset: anchor - center / scale, scale: scale),
          'meeting fingers must not discard centroid motion or reset the original pinch scale; radius=$radius',
        );
      }
      await second.up();
      await first.up();
    },
  );

  for (final motion in _Motion.values) {
    for (final delivery in _Delivery.values) {
      for (final frameHz in [60, 120]) {
        testWidgets(
          '${motion.name} / ${delivery.name} / 60Hz input / ${frameHz}Hz display',
          (tester) async {
            await pumpTouchCanvas(tester);
            final canvas = find.byType(LazyCanvas);
            final controller = tester.widget<LazyCanvas>(canvas).controller;
            if (motion == _Motion.combined) {
              controller.updateScalebyDelta(0.25, focalPoint: Offset.zero);
            }
            await tester.pump();
            final origin = tester.getTopLeft(canvas);
            final start = touchView(controller);
            final initial = _positions(motion, 0);
            final gestures = [
              await startTouchNavigation(
                tester,
                initial.$1 + origin,
                pointer: 1,
              ),
              await tester.startGesture(initial.$2 + origin, pointer: 2),
            ];
            final samples = _TouchSamples(start, initial, motion: motion);
            final report = TouchMotionReport();
            var now = Duration.zero;

            for (final step in _schedule(
              motion,
              delivery,
              inputHz: 60,
              frameHz: frameHz,
            )) {
              // Advancing input time must not manufacture a rendered frame.
              await tester.binding.delayed(step.time - now);
              now = step.time;
              if (step.finger case final finger?) {
                final position = step.position!;
                final previous = finger == 0
                    ? samples.arrived.$1
                    : samples.arrived.$2;
                if (position != previous) {
                  await gestures[finger].moveTo(
                    position + origin,
                    timeStamp: now,
                  );
                }
                samples.move(
                  now,
                  finger,
                  position,
                  sample: step.sample!,
                  last: step.last,
                );
              } else {
                await tester.pump();
              }

              final actual = touchView(controller);
              final context =
                  't=${now.inMicroseconds}us arrived=${samples.arrived} actual=$actual';
              expect(actual.offset.isFinite, isTrue, reason: context);
              expect(actual.scale.isFinite, isTrue, reason: context);
              expect(actual.scale, isPositive, reason: context);
              if (step.finger == null) {
                final painted = paintedTouchLandmarks(tester);
                final bounds = samples.frame(now);
                report.sample(
                  now,
                  painted,
                  permittedTouchView(bounds, painted),
                  '$context bounds=$bounds',
                );
              }
            }

            expectTouchView(
              touchView(controller),
              start,
              'the closed trace must return to its starting viewport',
            );
            await gestures[1].up(timeStamp: now);
            await gestures[0].up(timeStamp: now);
            debugPrint(
              'touch-replay ${motion.name}/${delivery.name}/60Hz-input/${frameHz}Hz-display: '
              'max-error=${report.maxError.toStringAsFixed(3)}px '
              'worst=${report.worstTime.inMicroseconds}us',
            );
            if (report.maxError >= touchTolerance) {
              debugPrint(report.worstContext);
            }
            report.verify();
          },
        );
      }
    }
  }
}

// ---------- Motion and delivery ----------

const _deliveryDelay = Duration(milliseconds: 4);
const _framePhase = Duration(milliseconds: 2);
const _gestureDuration = Duration(milliseconds: 500);

typedef _Step = ({
  Duration time,
  int? finger,
  Offset? position,
  int? sample,
  bool last,
});

enum _Motion { stationaryFinger, pan, pinch, combined, rotation, transitions }

enum _Delivery { paired, staggered, reversed }

TouchTouches _positions(_Motion motion, double progress) {
  final wave = math.sin(math.pi * progress);
  final pan = const Offset(72, 42) * wave;
  const first = Offset(250, 340);
  const second = Offset(490, 340);
  final center = (first + second) / 2;
  final scale = 1 + 0.25 * math.sin(2 * math.pi * progress);
  final radius =
      Offset(
        math.cos(2 * math.pi * progress),
        math.sin(2 * math.pi * progress),
      ) *
      120;
  return switch (motion) {
    _Motion.stationaryFinger => (first, second + pan),
    _Motion.pan => (first + pan, second + pan),
    _Motion.pinch => (
      center + (first - center) * scale,
      center + (second - center) * scale,
    ),
    _Motion.combined => (
      center + pan + (first - center) * scale,
      center + pan + (second - center) * scale,
    ),
    _Motion.rotation => (center - radius, center + radius),
    _Motion.transitions => _transitionPositions(progress, first, second),
  };
}

TouchTouches _transitionPositions(
  double progress,
  Offset first,
  Offset second,
) {
  const waypoints = [
    (Offset.zero, 1.0),
    (Offset(40, 20), 1.0),
    (Offset(40, 20), 1.2),
    (Offset(-25, 30), 0.9),
    (Offset(-25, 30), 1.0),
    (Offset.zero, 1.0),
  ];
  final phase = (progress * 5).floor().clamp(0, 4);
  final t = progress * 5 - phase;
  final pan = Offset.lerp(waypoints[phase].$1, waypoints[phase + 1].$1, t)!;
  final scale =
      waypoints[phase].$2 + (waypoints[phase + 1].$2 - waypoints[phase].$2) * t;
  final center = (first + second) / 2;
  return (
    center + pan + (first - center) * scale,
    center + pan + (second - center) * scale,
  );
}

/// Runs independent input and display clocks without exposing future input to frames.
/// Delivery order and display phase can place frames on either side of a touch update.
List<_Step> _schedule(
  _Motion motion,
  _Delivery delivery, {
  required int inputHz,
  required int frameHz,
  Duration framePhase = _framePhase,
}) {
  final steps = <_Step>[];
  final leading = delivery == _Delivery.reversed ? 1 : 0;
  for (var sample = 1; sample <= inputHz ~/ 2; sample++) {
    final time = Duration(
      microseconds: (sample * Duration.microsecondsPerSecond / inputHz).round(),
    );
    final target = _positions(motion, sample / (inputHz ~/ 2));
    steps.addAll([
      (
        time: time,
        finger: leading,
        position: leading == 0 ? target.$1 : target.$2,
        sample: sample,
        last: false,
      ),
      (
        time:
            time +
            (delivery == _Delivery.paired ? Duration.zero : _deliveryDelay),
        finger: 1 - leading,
        position: leading == 0 ? target.$2 : target.$1,
        sample: sample,
        last: true,
      ),
    ]);
  }
  final lastDeadline =
      _gestureDuration +
      _deliveryDelay +
      Duration(microseconds: (2 * 1000000 / frameHz).ceil());
  for (var frame = 0; ; frame++) {
    final time =
        framePhase +
        Duration(
          microseconds: (frame * Duration.microsecondsPerSecond / frameHz)
              .round(),
        );
    steps.add((
      time: time,
      finger: null,
      position: null,
      sample: null,
      last: false,
    ));
    if (time >= lastDeadline) break;
  }
  int deliveryOrder(_Step step) {
    if (step.finger == null) return 1;
    return step.last ? 0 : -1;
  }

  return steps..sort((a, b) {
    final time = a.time.compareTo(b.time);
    if (time != 0) return time;
    return deliveryOrder(a).compareTo(deliveryOrder(b));
  });
}

// ---------- Geometry checks and diagnostics ----------

// The target comes only from delivered positions, never the future trace.
class _InputSample {
  _InputSample(this.positions);
  TouchTouches positions;
  final changed = <int>{};
  bool complete = false;
  int? firstFrame;
}

class _TouchSamples {
  _TouchSamples(this.start, this.initial, {this.motion = _Motion.pan})
    : _arrived = initial;
  final TouchView start;
  final TouchTouches initial;
  final _Motion motion;
  TouchTouches _arrived;
  final _samples = <int, _InputSample>{};
  int _frame = 0;
  TouchTouches get arrived => _arrived;

  void move(
    Duration time,
    int finger,
    Offset position, {
    required int sample,
    bool last = false,
  }) {
    final input = _samples.putIfAbsent(sample, () => _InputSample(_arrived));
    if (position != (finger == 0 ? _arrived.$1 : _arrived.$2)) {
      input.changed.add(finger);
    }
    _arrived = finger == 0 ? (position, _arrived.$2) : (_arrived.$1, position);
    input
      ..positions = _arrived
      ..complete = last;
  }

  TouchBounds frame(Duration time) {
    var lower = start;
    var upper = start;
    for (final input in _samples.values) {
      if (input.changed.isEmpty) continue;
      final firstFrame = input.firstFrame ??= _frame;
      final due = _frame > firstFrame;
      // A lone event is indistinguishable from half a pan on its first frame.
      if (!input.complete || (!due && input.changed.length < 2)) continue;
      final view = expectedTouchView(start, initial, input.positions);
      upper = view;
      if (due) lower = view;
    }
    _frame++;
    return (lower: lower, upper: upper);
  }
}
