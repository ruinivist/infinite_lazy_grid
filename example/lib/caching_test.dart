import 'package:flutter/material.dart';
import 'package:infinite_lazy_grid/infinite_lazy_grid.dart';
import 'widgets/build_counter_widget.dart';

class CachingTestApp extends StatefulWidget {
  const CachingTestApp({super.key});

  @override
  State<CachingTestApp> createState() => _CachingTestAppState();
}

class _CachingTestAppState extends State<CachingTestApp> {
  final LazyCanvasController controller = LazyCanvasController(debug: false, buildCacheExtent: const Offset(50, 50));

  @override
  void initState() {
    super.initState();

    // Add some test widgets
    for (int i = 0; i < 20; i++) {
      controller.addChild(
        Offset((i % 5) * 120.0, (i ~/ 5) * 120.0),
        BuildCounterWidget(
          key: ValueKey<int>(i), // since in the tree it will be just an array at the same height, a count change
          // along the egdes of screen build all so you need a key to identify individually
          color: Colors.primaries[i % Colors.primaries.length],
          label: 'Widget $i',
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Widget Build Counts'),
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
      body: LazyCanvas(controller: controller),
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
