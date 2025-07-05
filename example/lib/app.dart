import 'package:flutter/material.dart';
import 'package:infinite_lazy_2d_grid/infinite_lazy_2d_grid.dart';

import 'widgets/fps.dart';

class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  final CanvasController controller = CanvasController(debug: true);

  @override
  void initState() {
    super.initState();
    for (int i = 0; i < 10; i++) {
      controller.addChild(
        Offset((i % 80) * 100.0, (i ~/ 80) * 100.0),
        (_) => GestureDetector(
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Tapped a container')));
            controller.focusOnChild(context, i);
          },
          child: InfoContainer(color: Colors.primaries[i % Colors.primaries.length]),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 8,
        children: [
          FloatingActionButton(
            onPressed: () {
              controller.updateScalebyDelta(0.1);
            },
            child: const Icon(Icons.zoom_in),
          ),
          FloatingActionButton(
            onPressed: () {
              controller.updateScalebyDelta(-0.1);
            },
            child: const Icon(Icons.zoom_out),
          ),
        ],
      ),
      body: Stack(
        children: [
          CanvasView(controller: controller, canvasBackground: SingleColorBackround(Colors.white)),
          Positioned(bottom: 16, left: 16, child: Fps()),
        ],
      ),
    );
  }
}

class InfoContainer extends StatelessWidget {
  final Color color;
  const InfoContainer({required this.color, super.key});

  @override
  Widget build(BuildContext context) {
    return Container(color: color, width: 50, height: 50);
  }
}
