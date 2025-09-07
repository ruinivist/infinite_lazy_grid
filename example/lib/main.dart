import 'simple_example.dart';
import './caching_test.dart';
import './dynamic_widget_example.dart';
import './render_callbacks_example.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(
    MaterialApp(
      // showPerformanceOverlay: true,
      title: 'Infinite Lazy 2D Grid Examples',
      home: const ExampleChooser(),
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Color(0xffffbf69))),
    ),
  );
}

class ExampleChooser extends StatelessWidget {
  const ExampleChooser({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Infinite Lazy Grid Examples')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => const SimpleExample()));
              },
              child: const Text('Simple Example'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => const CachingTestApp()));
              },
              child: const Text('Widget Build Counts'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => const DynamicWidgetExample()));
              },
              child: const Text('Widget State Updates'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => const RenderCallbacksExample()));
              },
              child: const Text('Render Callbacks Demo'),
            ),
            const SizedBox(height: 32),
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'Examples:\n'
                '• Simple: Basic usage demo\n'
                '• Build Counts: To see what rebuilds when\n'
                '• Dynamic Inputs: How to handle changing widget data\n'
                '• Render Callbacks: See widgets enter/exit render area',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
