import 'package:flutter/material.dart';
import 'package:infinite_lazy_grid/infinite_lazy_grid.dart';

enum _Navigation { defaults, disabled, custom }

class NavigationExample extends StatefulWidget {
  const NavigationExample({super.key});

  @override
  State<NavigationExample> createState() => _NavigationExampleState();
}

class _NavigationExampleState extends State<NavigationExample> {
  final controller = LazyCanvasController(minScale: 0.25, maxScale: 4);
  var navigation = _Navigation.defaults;

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < 12; i++) {
      controller.addChild(
        Offset(40 + (i % 4) * 160, 40 + (i ~/ 4) * 120),
        Container(
          width: 120,
          height: 80,
          color: Colors.primaries[i],
          alignment: Alignment.center,
          child: Text('Node ${i + 1}'),
        ),
      );
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Navigation')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: SegmentedButton<_Navigation>(
            segments: const [
              ButtonSegment(
                value: _Navigation.defaults,
                label: Text('Default'),
              ),
              ButtonSegment(
                value: _Navigation.disabled,
                label: Text('Disabled'),
              ),
              ButtonSegment(value: _Navigation.custom, label: Text('Custom')),
            ],
            selected: {navigation},
            onSelectionChanged: (values) {
              controller.stopAnimation();
              setState(() => navigation = values.single);
            },
          ),
        ),
        Text(switch (navigation) {
          _Navigation.defaults => 'Drag, pinch, use your trackpad, or scroll.',
          _Navigation.disabled =>
            'Navigation is disabled; the viewport stays still.',
          _Navigation.custom =>
            'Flutter drag and pinch gestures; wheel navigation is disabled.',
        }),
        const SizedBox(height: 16),
        Expanded(
          child: LazyCanvas(
            controller: controller,
            navigationBuilder: switch (navigation) {
              _Navigation.defaults => null,
              _Navigation.disabled => (_, child) => child,
              _Navigation.custom => (_, child) => GestureDetector(
                behavior: HitTestBehavior.translucent,
                onScaleStart: controller.onScaleStart,
                onScaleUpdate: controller.onScaleUpdate,
                onScaleEnd: controller.onScaleEnd,
                child: child,
              ),
            },
          ),
        ),
      ],
    ),
  );
}
