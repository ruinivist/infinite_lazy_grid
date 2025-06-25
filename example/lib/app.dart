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
    return Scaffold(body: InfiniteLazy2dGrid());
  }
}
