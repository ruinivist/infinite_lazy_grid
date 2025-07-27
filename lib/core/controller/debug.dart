part of 'controller.dart';

class _Debug extends StatelessWidget {
  final CanvasChildId id;
  final Offset gs, ss;
  final Widget child;

  const _Debug({required this.id, required this.gs, required this.ss, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          left: 0,
          bottom: -60,
          child: Text(
            'ID: $id\nGS:(${gs.dx.toInt()},${gs.dy.toInt()})\nSS:(${ss.dx.toInt()},${ss.dy.toInt()})',
            style: monospaceStyle,
          ),
        ),
      ],
    );
  }
}
