import './app.dart';
import './caching_test.dart';
import './dynamic_widget_example.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(
    MaterialApp(
      // showPerformanceOverlay: true,
      title: 'Infinite Lazy 2D Grid Example',
      home: const ExampleChooser(),
      debugShowCheckedModeBanner: false,
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
                Navigator.push(context, MaterialPageRoute(builder: (context) => const App()));
              },
              child: const Text('Original Example'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => const CachingTestApp()));
              },
              child: const Text('Widget Caching Test'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => const DynamicWidgetExample()));
              },
              child: const Text('Dynamic Widget Inputs'),
            ),
            const SizedBox(height: 32),
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'Examples:\n'
                '• Original: Basic usage demo\n'
                '• Caching Test: Shows Flutter\'s automatic widget optimization\n'
                '• Dynamic Inputs: How to handle changing widget data',
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
