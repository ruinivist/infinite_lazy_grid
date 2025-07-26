import 'package:flutter/material.dart';

/// A widget that displays how many times it has been built.
/// Useful for demonstrating widget caching optimization.
class BuildCounterWidget extends StatefulWidget {
  final Color color;
  final String label;

  const BuildCounterWidget({super.key, required this.color, required this.label});

  @override
  State<BuildCounterWidget> createState() => _BuildCounterWidgetState();
}

class _BuildCounterWidgetState extends State<BuildCounterWidget> {
  static final Map<String, int> _buildCounts = {};

  @override
  Widget build(BuildContext context) {
    final count = _buildCounts[widget.label] = (_buildCounts[widget.label] ?? 0) + 1;

    debugPrint('Building ${widget.label} - Build count: $count');

    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: widget.color,
        border: Border.all(color: Colors.black, width: 2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            widget.label,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text('Builds: $count', style: const TextStyle(color: Colors.white, fontSize: 10)),
        ],
      ),
    );
  }
}
