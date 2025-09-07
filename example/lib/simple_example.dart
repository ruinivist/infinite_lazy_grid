import 'package:flutter/material.dart';
import 'package:infinite_lazy_grid/infinite_lazy_grid.dart';

import 'widgets/fps.dart';

class SimpleExample extends StatefulWidget {
  const SimpleExample({super.key});

  @override
  State<SimpleExample> createState() => _SimpleExampleState();
}

class _SimpleExampleState extends State<SimpleExample> {
  final LazyCanvasController controller = LazyCanvasController(debug: true, buildCacheExtent: const Offset(50, 50));
  final List<CanvasChildId> childIds = [];

  @override
  void initState() {
    super.initState();
    for (int i = 0; i < 10; i++) {
      final id = controller.addChild(
        Offset((i % 80) * 100.0, (i ~/ 80) * 100.0),
        GestureDetector(
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Tapped a container')));
            controller.focusOnChild(childIds[i]);
          },
          child: InfoContainer(color: Colors.primaries[i % Colors.primaries.length]),
        ),
      );
      childIds.add(id);
    }
    controller.addChild(
      const Offset(0, 200),
      Container(
        width: 300,
        height: 150,
        color: Colors.grey[200],
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              'This is a very long text inside a scrollable container. '
              'You can scroll to see more content. '
              'Lorem ipsum dolor sit amet, consectetur adipiscing elit. '
              'Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. '
              'Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. '
              'Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur.',
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Simple Example')),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 8,
        children: [
          FloatingActionButton(
            heroTag: 'app_zoom_in',
            onPressed: () {
              controller.updateScalebyDelta(0.1);
            },
            child: const Icon(Icons.zoom_in),
          ),
          FloatingActionButton(
            heroTag: 'app_zoom_out',
            onPressed: () {
              controller.updateScalebyDelta(-0.1);
            },
            child: const Icon(Icons.zoom_out),
          ),
        ],
      ),
      body: Stack(
        children: [
          LazyCanvas(controller: controller),
          Positioned(bottom: 64, left: 16, child: Fps()),
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
