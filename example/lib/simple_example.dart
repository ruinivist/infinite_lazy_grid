import 'package:flutter/material.dart';
import 'package:infinite_lazy_grid/infinite_lazy_grid.dart';

import 'widgets/fps.dart';

class SimpleExample extends StatefulWidget {
  const SimpleExample({super.key});

  @override
  State<SimpleExample> createState() => _SimpleExampleState();
}

class _SimpleExampleState extends State<SimpleExample> {
  late final LazyCanvasController controller;

  @override
  void initState() {
    final cacheExtent = const Offset(50, 50);
    controller = LazyCanvasController(debug: true, buildCacheExtent: cacheExtent);
    final List<CanvasChildId> childIds = [];

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

    final trackId = controller.addChild(
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

    controller.addChild(const Offset(330, 200), _PositionTracker(controller: controller, childId: trackId));
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

class _PositionTracker extends StatefulWidget {
  final LazyCanvasController controller;
  final CanvasChildId childId;
  const _PositionTracker({required this.controller, required this.childId});

  @override
  State<_PositionTracker> createState() => _PositionTrackerState();
}

class _PositionTrackerState extends State<_PositionTracker> {
  late final VoidCallback _listener;

  @override
  void initState() {
    super.initState();
    _listener = () {
      if (mounted) setState(() {});
    };
    widget.controller.addListener(_listener);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_listener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final childPosition = widget.controller
        .widgetsWithScreenPositions()
        .where((e) => e.id == widget.childId)
        .firstOrNull;

    final visible = childPosition != null;
    final borderColor = visible ? Colors.green : Colors.red;
    final icon = visible ? Icons.visibility : Icons.visibility_off;
    final statusText = visible ? 'Visible' : 'Off screen';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(left: BorderSide(color: borderColor, width: 4)),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(10), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This example uses tight build extents so you can see the text box get unmounted when its position ( top left ) goes off screen.\nIncrease it in your app.',
            style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: borderColor),
              const SizedBox(width: 6),
              Text(
                statusText,
                style: TextStyle(color: borderColor, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Cache extent: ${widget.controller.buildCacheExtent}',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 13),
          ),
          const SizedBox(height: 6),
          if (visible)
            Text(
              'Text box position: ${childPosition.ssPosition}',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 13),
            )
          else
            const Text('Text box is off screen', style: TextStyle(fontSize: 13)),
          const SizedBox(height: 16),
          Text(
            'Note: due to spatial hashing the offset is an approximate, not a pixel-perfect measure.',
            style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withAlpha(200)),
          ),
        ],
      ),
    );
  }
}
