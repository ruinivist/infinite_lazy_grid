import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class Fps extends StatefulWidget {
  const Fps({super.key});

  @override
  State<Fps> createState() => _FpsState();
}

class _FpsState extends State<Fps> {
  @override
  void initState() {
    SchedulerBinding.instance.addPersistentFrameCallback(_frame);
    super.initState();
  }

  int _lastFrameTime = 0;
  String _frameRate = "0 fps";
  void _frame(Duration elapsed) {
    int elapsedMicroseconds = elapsed.inMicroseconds;
    double elapsedSeconds = (elapsedMicroseconds - _lastFrameTime) * 1e-6;
    if (elapsedSeconds != 0) {
      _lastFrameTime = elapsedMicroseconds;
      if (mounted) {
        setState(() {
          _frameRate = '${(1.0 / elapsedSeconds).toStringAsFixed(2)} fps';
        });
      }
    }
    // redraw if mounted
    if (mounted) {
      SchedulerBinding.instance.scheduleFrame();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Text(_frameRate);
  }
}
