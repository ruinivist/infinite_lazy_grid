import 'package:flutter/material.dart';
import 'package:infinite_lazy_2d_grid/utils/conversions.dart';
import 'package:infinite_lazy_2d_grid/utils/styles.dart';

// ------------------------------ Public Types -------------------------------

typedef WidgetBuilder = Widget Function();

// ------------------------------ Private Types ------------------------------

// some simple exceptions
// ignore: non_constant_identifier_names
final _ChildNotFoundException = Exception('Child with the given ID does not exist');

class _CanvasItem {
  Offset gsPosition;
  final WidgetBuilder builder;

  _CanvasItem({required this.gsPosition, required this.builder});
}

// ------------------------------ Controller ------------------------------

/// Every canvas view needs one and this handles the positioning logic
class CanvasController with ChangeNotifier {
  int _nextId = 0; // surely we won't run out of IDs, Clueless
  Offset _gsTopLeftOffset = Offset.zero;
  final Map<int, _CanvasItem> _children = {}; // int for IDs
  bool debug;

  CanvasController({this.debug = false});

  // -------------------- getters --------------------
  Offset get offset => _gsTopLeftOffset;

  // -------------------- public functions --------------------

  // -------- child manip --------

  int addChild(Offset position, WidgetBuilder builder) {
    _children[_nextId] = _CanvasItem(gsPosition: position, builder: builder);
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

  // -------- gesture handling --------
  void handleGesture(ScaleUpdateDetails details) {
    // handle gestures like pinch to zoom, pan, etc.

    // convention is that if I drag from right to left, dx is negative
    // for top to bottom, dy is postive ( so usual display conventions and final vector postion - initial vector position )
    final delta = details.focalPointDelta;

    _gsTopLeftOffset -= delta;

    notifyListeners();
  }

  List<(Offset, Widget)> widgetsWithScreenPositions() {
    return _children.entries.map((entry) {
      final item = entry.value;
      final ssPosition = gsToSs(item.gsPosition, _gsTopLeftOffset);
      var child = item.builder();
      if (debug) child = _Debug(id: entry.key, gs: item.gsPosition, ss: ssPosition, child: child);
      return (ssPosition, child);
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
