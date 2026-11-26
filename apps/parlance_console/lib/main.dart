import 'package:material_ui/material_ui.dart';

import 'src/console/client.dart';
import 'src/console/live.dart';
import 'src/console/transport_web.dart'
    if (dart.library.io) 'src/console/transport_io.dart';
import 'src/home.dart';
import 'src/remote.dart';
import 'src/viewer.dart';

/// The desktop launcher supplies MCP. The web viewer supports journal URLs.
void main() {
  final viewer = Viewer();
  runApp(ParlanceConsoleApp(viewer: viewer, client: connectWindow()));
  if (Uri.base.queryParameters['journal'] case final url?) {
    loadFrom(viewer, Uri.base.resolve(url));
  }
}

/// Live host diagnostics and offline journal playback.
class ParlanceConsoleApp extends StatelessWidget {
  const ParlanceConsoleApp({super.key, required this.viewer, this.client});

  final Viewer viewer;
  final ConsoleClient? client;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Parlance Console',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF4C9AFF),
        brightness: Brightness.dark,
      ),
      visualDensity: VisualDensity.compact,
    ),
    home: client == null
        ? Home(viewer: viewer)
        : LiveConsole(viewer: viewer, client: client!),
  );
}
