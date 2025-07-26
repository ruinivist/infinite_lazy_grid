import 'package:flutter/material.dart';
import 'package:infinite_lazy_grid/infinite_lazy_grid.dart';
import 'widgets/build_counter_widget.dart';

class CachingTestApp extends StatefulWidget {
  const CachingTestApp({super.key});

  @override
  State<CachingTestApp> createState() => _CachingTestAppState();
}

class _CachingTestAppState extends State<CachingTestApp> {
  final LazyCanvasController controller = LazyCanvasController(debug: false);

  @override
  void initState() {
    super.initState();

    // Add some test widgets
    for (int i = 0; i < 20; i++) {
      controller.addChild(
        Offset((i % 5) * 120.0, (i ~/ 5) * 120.0),
        BuildCounterWidget(color: Colors.primaries[i % Colors.primaries.length], label: 'Widget $i'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Widget Caching Test'),
        actions: [
          IconButton(
            onPressed: () {
              // Force a rebuild by calling notifyListeners
              // In this new approach, Flutter handles the caching
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Flutter automatically handles widget caching - no manual invalidation needed!'),
                ),
              );
            },
            icon: const Icon(Icons.refresh),
            tooltip: 'Flutter Auto-Caching Info',
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.yellow[100],
            child: const Text(
              'Instructions:\n'
              '• Pan around the canvas - widgets should only build once initially\n'
              '• Watch the console for build messages\n'
              '• Use the refresh button to force rebuilds\n'
              '• Zoom in/out to see caching in action',
              style: TextStyle(fontSize: 12),
            ),
          ),
          Expanded(
            child: LazyCanvas(controller: controller, canvasBackground: const DotGridBackround()),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            heroTag: 'zoom_in',
            onPressed: () => controller.updateScalebyDelta(0.1),
            child: const Icon(Icons.zoom_in),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            heroTag: 'zoom_out',
            onPressed: () => controller.updateScalebyDelta(-0.1),
            child: const Icon(Icons.zoom_out),
          ),
        ],
      ),
    );
  }
}
