import 'package:flutter/material.dart';
import 'package:infinite_lazy_grid/infinite_lazy_grid.dart';
import 'widgets/fps.dart';

class RenderCallbacksExample extends StatefulWidget {
  const RenderCallbacksExample({super.key});

  @override
  State<RenderCallbacksExample> createState() => _RenderCallbacksExampleState();
}

class _RenderCallbacksExampleState extends State<RenderCallbacksExample> {
  late final LazyCanvasController controller;
  final List<CanvasChildId> childIds = [];
  final List<String> logs = [];
  final ScrollController logScrollController = ScrollController();

  void onWidgetEnteredRender(CanvasChildId id) {
    _addLog('Widget $id entered render area', Colors.green);
  }

  void onWidgetExitedRender(CanvasChildId id) {
    _addLog('Widget $id exited render area', Colors.red);
  }

  @override
  void initState() {
    super.initState();

    // Initialize controller with render callbacks
    controller = LazyCanvasController(
      debug: true,
      onWidgetEnteredRender: onWidgetEnteredRender,
      onWidgetExitedRender: onWidgetExitedRender,
    );

    _createGrid();
  }

  void _createGrid() {
    // Create a 10x10 grid of widgets
    for (int row = 0; row < 4; row++) {
      for (int col = 0; col < 4; col++) {
        final id = controller.addChild(
          Offset(col * 180.0, row * 180.0),
          GridItem(row: row, col: col, color: Colors.primaries[(row * 10 + col) % Colors.primaries.length]),
        );
        childIds.add(id);
      }
    }
  }

  void _addLog(String message, Color color) {
    setState(() {
      logs.insert(0, message);
      // Keep only the last 50 logs
      if (logs.length > 50) {
        logs.removeRange(50, logs.length);
      }
    });

    // Auto-scroll to top of logs
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (logScrollController.hasClients) {
        logScrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  void _clearLogs() {
    setState(() {
      logs.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Render Callbacks Example')),
      body: Stack(
        children: [
          LazyCanvas(controller: controller),

          // FPS counter
          const Positioned(bottom: 16, left: 16, child: Fps()),

          // Logs panel
          Positioned(
            top: 16,
            right: 16,
            child: Container(
              width: 350,
              height: 400,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.8),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey),
              ),
              child: Column(
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: Colors.blue,
                      borderRadius: BorderRadius.only(topLeft: Radius.circular(8), topRight: Radius.circular(8)),
                    ),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Render Callbacks Log',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                        IconButton(
                          onPressed: _clearLogs,
                          icon: const Icon(Icons.clear, color: Colors.white),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                  ),

                  // Logs list
                  Expanded(
                    child: logs.isEmpty
                        ? const Center(
                            child: Text(
                              'Pan around to see render callbacks',
                              style: TextStyle(color: Colors.grey),
                              textAlign: TextAlign.center,
                            ),
                          )
                        : ListView.builder(
                            controller: logScrollController,
                            padding: const EdgeInsets.all(8),
                            itemCount: logs.length,
                            itemBuilder: (context, index) {
                              final log = logs[index];
                              final isEntered = log.contains('entered');
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Row(
                                  children: [
                                    Icon(
                                      isEntered ? Icons.add_circle : Icons.remove_circle,
                                      color: isEntered ? Colors.green : Colors.red,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        log,
                                        style: TextStyle(
                                          color: isEntered ? Colors.green : Colors.red,
                                          fontSize: 12,
                                          fontFamily: 'monospace',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    logScrollController.dispose();
    super.dispose();
  }
}

class GridItem extends StatelessWidget {
  final int row;
  final int col;
  final Color color;

  const GridItem({super.key, required this.row, required this.col, required this.color});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Tapped grid item ($row, $col)'), duration: const Duration(seconds: 1)));
      },
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          color: color,
          border: Border.all(color: Colors.black, width: 1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$row',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
              Text(
                '$col',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
