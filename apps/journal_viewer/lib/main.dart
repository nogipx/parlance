import 'package:flutter/material.dart';

import 'src/home.dart';
import 'src/remote.dart';
import 'src/viewer.dart';

/// Opens empty, or with the journal `?journal=<url>` names, relative to
/// where the viewer is served from: a link to a journal opens it.
void main() {
  final viewer = Viewer();
  runApp(JournalViewerApp(viewer: viewer));
  if (Uri.base.queryParameters['journal'] case final url?) {
    loadFrom(viewer, Uri.base.resolve(url));
  }
}

/// Conversations of a parlance journal: loaded from files, drawn as trees
/// on their time, and played back as they happened.
class JournalViewerApp extends StatelessWidget {
  const JournalViewerApp({super.key, required this.viewer});

  final Viewer viewer;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Journal',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF4C9AFF),
        brightness: Brightness.dark,
      ),
      visualDensity: VisualDensity.compact,
    ),
    home: Home(viewer: viewer),
  );
}
