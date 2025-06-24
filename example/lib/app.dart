import 'package:flutter/material.dart';
import 'package:infinite_lazy_2d_grid/infinite_lazy_2d_grid.dart';

class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  Offset _dragStartFocalPoint = Offset.zero;
  Offset _lastFocalPoint = Offset.zero;
  Offset _offset = Offset.zero;
  double _scale = 1.0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CanvasView(
        children: [
          Container(width: 100, height: 100, color: Colors.red),
          Container(width: 100, height: 100, color: Colors.green),
          Container(width: 100, height: 100, color: Colors.blue),
        ],
        positions: [
          Offset(0, 0), // Position for red container
          Offset(200, 0), // Position for green container
          Offset(400, 0), // Position for blue container
        ],
        offset: _offset,
        scale: _scale,
        handleScaleUpdate: (details) {
          // double dampeningFactor = 0.1;
          // double scaleDelta = (details.scale - 1) * dampeningFactor;
          // double newScale = _scale * (1 + scaleDelta);
          // newScale = newScale.clamp(0.4, 4.0);

          // focal point in the coordinate system of the grid
          Offset focalPoint = details.localFocalPoint;
          Offset gridFocalPoint = (_offset + focalPoint) / _scale;

          // new scale set
          // _scale = newScale;

          // adjust offset to keep the focal point stationary
          _offset = gridFocalPoint * _scale - focalPoint;

          // panning
          if (_lastFocalPoint != null) {
            // right is positive, down is positive
            Offset delta = -(details.focalPoint - _lastFocalPoint!); //inverse panning (natural)
            const sensitivity = 1.0; // Adjust sensitivity as needed
            _offset += delta * sensitivity;
          }
          _lastFocalPoint = details.focalPoint;
          setState(() {});
        },
        handleScaleStart: (details) {
          _lastFocalPoint = details.localFocalPoint;
          _dragStartFocalPoint = details.localFocalPoint;
          setState(() {});
        },
        canvasBackground: const SingleColorBackround(Colors.white),
      ),
    );
  }
}
