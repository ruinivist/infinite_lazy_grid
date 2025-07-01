import 'package:flutter/material.dart';
import 'package:infinite_lazy_2d_grid/core/controller.dart';
import 'package:infinite_lazy_2d_grid/infinite_lazy_2d_grid.dart';

class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  final CanvasController controller = CanvasController();

  @override
  void initState() {
    super.initState();

    controller.addChild(const Offset(100, 100), () => const InfoContainer(color: Colors.red));
    controller.addChild(const Offset(200, 200), () => const InfoContainer(color: Colors.green));
    controller.addChild(const Offset(300, 300), () => const InfoContainer(color: Colors.blue));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CanvasView(controller: controller, canvasBackground: SingleColorBackround(Colors.white)),
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
