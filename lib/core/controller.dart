import 'package:flutter/material.dart';
import 'package:infinite_lazy_2d_grid/utils/conversions.dart';
import 'package:infinite_lazy_2d_grid/utils/styles.dart';

// ------------------------------ Public Types -------------------------------

typedef WidgetBuilder = Widget Function();

// ------------------------------ Private Types ------------------------------

// some simple exceptions
// ignore: non_constant_identifier_names
final _ChildNotFoundException = Exception('Child with the given ID does not exist');

class _ChildInfo {
  Offset gsPosition;
  final WidgetBuilder builder;

  _ChildInfo({required this.gsPosition, required this.builder});
}

class ChildInfo {
  Offset gsPosition;
  Offset ssPosition;
  Widget child;
  ChildInfo({required this.gsPosition, required this.ssPosition, required this.child});
}

// ------------------------------ Controller ------------------------------

/// Every canvas view needs one and this handles the positioning logic
class CanvasController with ChangeNotifier {
  int _nextId = 0; // surely we won't run out of IDs, Clueless
  Offset _gsTopLeftOffset = Offset.zero;
  double _baseScale, _scale;
  late Size _canvasSize;
  final Map<int, _ChildInfo> _children = {}; // int for IDs
  bool debug;

  CanvasController({this.debug = false, double initialScale = 1})
    : _scale = initialScale,
      _baseScale = initialScale,
      assert(initialScale > 0, 'Initial scale must be greater than 0');

  // -------------------- getters --------------------
  Offset get offset => _gsTopLeftOffset;
  double get scale => _scale;
  Size get canvasSize => _canvasSize;
  // -------------------- public functions --------------------

  void onCanvasSizeChange(Size size) {
    _canvasSize = size;
  }

  // -------- child manip --------

  int addChild(Offset position, WidgetBuilder builder) {
    _children[_nextId] = _ChildInfo(gsPosition: position, builder: builder);
    return _nextId++;
  }

  void removeChild(int id) {
    _children.remove(id);
  }

  int updatePosition(int id, Offset newPosition) {
    if (_children.containsKey(id)) {
      _children[id]!.gsPosition = newPosition;
      return id;
    } else {
      throw _ChildNotFoundException;
    }
  }

  Offset getPosition(int id) {
    if (_children.containsKey(id)) {
      return _children[id]!.gsPosition;
    } else {
      throw _ChildNotFoundException;
    }
  }

  void onScaleStart(ScaleStartDetails details) {
    _baseScale = _scale;
  }

  // -------- gesture handling --------
  void onScaleUpdate(ScaleUpdateDetails details) {
    // uses usual display conventions and final vector postion - initial vector position
    // convention is that if I drag from right to left, dx is negative
    // for top to bottom, dy is postive

    // scale + offset is => scale then offset

    if (details.scale != 1) {
      final newScale = _baseScale * details.scale;
      _gsTopLeftOffset = newGsTopLeftOnScaling(_gsTopLeftOffset, details.localFocalPoint, _scale, newScale);
      _scale = newScale;
    }

    if (details.focalPointDelta != Offset.zero) {
      // if ss distnace is x, and zoom is 2x, gs only moves by x/2
      _gsTopLeftOffset -= details.focalPointDelta / _scale;
    }

    notifyListeners();
  }

  void updateScalebyDelta(double delta) {
    final focalPoint = Offset(canvasSize.width / 2, canvasSize.height / 2);
    final newScale = _scale + delta;
    _gsTopLeftOffset = newGsTopLeftOnScaling(_gsTopLeftOffset, focalPoint, _scale, newScale);
    _scale = newScale;
    notifyListeners();
  }

  List<ChildInfo> widgetsWithScreenPositions() {
    return _children.entries.map((entry) {
      final item = entry.value;
      final ssPosition = gsToSs(item.gsPosition, _gsTopLeftOffset, _scale);
      var child = item.builder();
      if (debug) child = _Debug(id: entry.key, gs: item.gsPosition, ss: ssPosition, child: child);
      return ChildInfo(gsPosition: item.gsPosition, ssPosition: ssPosition, child: child);
    }).toList();
  }
}

class _Debug extends StatelessWidget {
  final int id;
  final Offset gs, ss;
  final Widget child;

  const _Debug({required this.id, required this.gs, required this.ss, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          left: 0,
          bottom: -60,
          child: Text(
            'ID: $id\nGS:(${gs.dx.toInt()},${gs.dy.toInt()})\nSS:(${ss.dx.toInt()},${ss.dy.toInt()})',
            style: monospaceStyle,
          ),
        ),
      ],
    );
  }
}
