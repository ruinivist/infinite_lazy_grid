import 'package:flutter/material.dart';
import 'package:infinite_lazy_grid/infinite_lazy_grid.dart';

/// Demo showing different approaches to handle dynamic widget inputs
class DynamicWidgetExample extends StatefulWidget {
  const DynamicWidgetExample({super.key});

  @override
  State<DynamicWidgetExample> createState() => _DynamicWidgetExampleState();
}

class _DynamicWidgetExampleState extends State<DynamicWidgetExample> {
  final LazyCanvasController controller = LazyCanvasController(debug: false);

  // Simulate some dynamic data
  int counter = 0;
  String message = "Hello World";
  Color selectedColor = Colors.blue;

  @override
  void initState() {
    super.initState();
    _setupWidgets();
  }

  void _setupWidgets() {
    // Approach 1: Using StatefulWidget with GlobalKey to preserve state
    controller.addChild(const Offset(0, 0), SelfManagedCounterWidget(key: GlobalKey(), label: "Self-Managed"));

    // Approach 2: Using updateChildWidget, though since before and after it's still just as the same ExternalDataWidget
    // you need to have the key change as an arg change is separated from the tree
    controller.addChild(
      const Offset(200, 0),
      ExternalDataWidget(key: ValueKey('external_$counter'), counter: counter, message: message, color: selectedColor),
    );

    // Approach 3: Using ValueListenableBuilder for reactive updates
    controller.addChild(
      const Offset(400, 0),
      ValueListenableBuilder<int>(
        valueListenable: _counterNotifier,
        builder: (context, count, child) {
          return Container(
            width: 120,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.green,
              border: Border.all(color: Colors.black, width: 2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                'Reactive: $count',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          );
        },
      ),
    );
  }

  final ValueNotifier<int> _counterNotifier = ValueNotifier<int>(0);

  void _updateExternalData() {
    setState(() {
      counter++;
      message = "Updated $counter times";
      selectedColor = Colors.primaries[counter % Colors.primaries.length];
    });

    // Approach 2: Update the widget when external data changes
    // Use ValueKey to ensure Flutter recognizes this as a different widget
    controller.updateChildWidget(
      1, // Widget ID (second widget added)
      ExternalDataWidget(
        key: ValueKey('external_$counter'), // Force rebuild with unique key
        counter: counter,
        message: message,
        color: selectedColor,
      ),
    );
  }

  void _updateReactiveWidget() {
    _counterNotifier.value++;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dynamic Widget Inputs')),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey[100],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Four approaches for dynamic inputs:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('1. Self-managed StatefulWidget with GlobalKey - preserves state when off-screen'),
                const Text('2. External data + updateChildWidget (center) - manual updates'),
                const Text('3. ValueListenableBuilder (right) - reactive updates'),
                const SizedBox(height: 16),
                Row(
                  children: [
                    ElevatedButton(onPressed: _updateExternalData, child: Text('Update External Data ($counter)')),
                    const SizedBox(width: 16),
                    ElevatedButton(
                      onPressed: _updateReactiveWidget,
                      child: Text('Update Reactive Widget (${_counterNotifier.value})'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: LazyCanvas(controller: controller, canvasBackground: const DotGridBackround()),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _counterNotifier.dispose();
    super.dispose();
  }
}

/// Approach 1: StatefulWidget that manages its own state
class SelfManagedCounterWidget extends StatefulWidget {
  final String label;

  const SelfManagedCounterWidget({super.key, required this.label});

  @override
  State<SelfManagedCounterWidget> createState() => _SelfManagedCounterWidgetState();
}

class _SelfManagedCounterWidgetState extends State<SelfManagedCounterWidget> {
  int _count = 0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _count++;
        });
      },
      child: Container(
        width: 120,
        height: 80,
        decoration: BoxDecoration(
          color: Colors.purple,
          border: Border.all(color: Colors.black, width: 2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(widget.label, style: const TextStyle(color: Colors.white, fontSize: 10)),
            Text(
              'Count: $_count',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            const Text('(Tap me)', style: TextStyle(color: Colors.white70, fontSize: 10)),
          ],
        ),
      ),
    );
  }
}

/// Approach 2: Widget that depends on external data
class ExternalDataWidget extends StatelessWidget {
  final int counter;
  final String message;
  final Color color;

  const ExternalDataWidget({super.key, required this.counter, required this.message, required this.color});

  @override
  Widget build(BuildContext context) {
    debugPrint('ExternalDataWidget built with counter: $counter, key: $key');

    return Container(
      width: 120,
      height: 80,
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: Colors.black, width: 2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('External', style: TextStyle(color: Colors.white, fontSize: 10)),
          Text(
            'Count: $counter',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
          ),
          Text(
            message,
            style: const TextStyle(color: Colors.white, fontSize: 8),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
