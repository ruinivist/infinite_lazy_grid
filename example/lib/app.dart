import 'package:flutter/material.dart';
import 'package:infinite_lazy_2d_grid/infinite_lazy_2d_grid.dart';

class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SizedBox.expand(
        child: CanvasView(
          ssPositions: [Offset(100, 100), Offset(200, 200), Offset(300, 300)],
          canvasBackground: SingleColorBackround(Colors.white),
          children: [
            InfoContainer(color: Colors.red),
            InfoContainer(color: Colors.green),
            InfoContainer(color: Colors.blue),
          ],
        ),
      ),
    );
  }
}

class InfoContainer extends StatelessWidget {
  final Color color;
  const InfoContainer({required this.color, super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        print("tapped");
      },
      child: Container(color: color, width: 50, height: 50),
    );
  }
}
