import 'dart:convert';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'conversations.dart';
import 'details.dart';
import 'playback.dart';
import 'viewer.dart';
import 'waterfall.dart';

/// The viewer: journal files opened or dropped; the conversations on the
/// left, the one chosen as a tree in the middle, the message chosen on the
/// right, playback below.
class Home extends StatefulWidget {
  const Home({super.key, required this.viewer});

  final Viewer viewer;

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  bool _dragging = false;

  Viewer get v => widget.viewer;

  Future<void> _open() async {
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: 'Journal files',
      type: FileType.custom,
      allowedExtensions: const ['jsonl', 'json', 'txt'],
      allowMultiple: true,
      withData: true,
    );
    if (picked == null) return;
    _load([
      for (final f in picked.files)
        if (f.bytes case final b?)
          (name: f.name, text: utf8.decode(b, allowMalformed: true)),
    ]);
  }

  Future<void> _drop(DropDoneDetails d) async {
    setState(() => _dragging = false);
    _load([
      for (final f in d.files) (name: f.name, text: await f.readAsString()),
    ]);
  }

  void _load(List<JournalFile> files) {
    if (files.isNotEmpty) v.load(files);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: _drop,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Journal'),
          titleSpacing: 16,
          actions: [
            ListenableBuilder(
              listenable: v,
              builder: (context, _) => v.entries.isEmpty
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Center(
                        child: Text(
                          '${v.files.length} '
                          '${v.files.length == 1 ? 'file' : 'files'}, '
                          '${v.entries.length} entries, '
                          '${v.all.length} conversations',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton.tonalIcon(
                onPressed: _open,
                icon: const Icon(Icons.folder_open, size: 18),
                label: const Text('Open'),
              ),
            ),
          ],
        ),
        body: Stack(
          children: [
            ListenableBuilder(
              listenable: v,
              builder: (context, _) => v.entries.isEmpty
                  ? _Empty(error: v.problem, onOpen: _open)
                  : Column(
                      children: [
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(
                                width: 340,
                                child: ConversationList(viewer: v),
                              ),
                              const VerticalDivider(width: 1),
                              Expanded(child: Waterfall(viewer: v)),
                              const VerticalDivider(width: 1),
                              SizedBox(width: 380, child: Details(viewer: v)),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        PlaybackBar(viewer: v),
                      ],
                    ),
            ),
            if (_dragging)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    color: theme.colorScheme.primary.withValues(alpha: 0.12),
                    alignment: Alignment.center,
                    child: Text(
                      'Drop to open',
                      style: theme.textTheme.headlineSmall,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.error, required this.onOpen});

  final String? error;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.account_tree_outlined,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'Drop journal files here, or open them',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'A parlance journal is JSON lines, a file a day '
              '(journal-2026-10-28.jsonl). Tephra keeps it in '
              '~/Library/Application Support/Tephra/journal.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            if (error case final e?) ...[
              const SizedBox(height: 12),
              Text(
                e,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onOpen,
              icon: const Icon(Icons.folder_open),
              label: const Text('Open'),
            ),
          ],
        ),
      ),
    );
  }
}
