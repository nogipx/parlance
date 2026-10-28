import 'dart:io';

/// The UTC day of [at]: `2026-10-28`.
String dayOf(DateTime at) => at.toUtc().toIso8601String().substring(0, 10);

String fileOfDay(String day) => 'journal-$day.jsonl';

final _name = RegExp(r'^journal-(\d{4}-\d{2}-\d{2})\.jsonl$');

/// The journal's files in [dir] with their days, the oldest first.
List<(String, File)> journalFiles(Directory dir) {
  if (!dir.existsSync()) return const [];
  return [
    for (final f in dir.listSync().whereType<File>())
      if (_name.firstMatch(f.uri.pathSegments.last) case final m?)
        (m.group(1)!, f),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
}
