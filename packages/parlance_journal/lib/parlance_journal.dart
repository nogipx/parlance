/// A registry's journal (parlance SPEC §9.3) kept where it lasts: written
/// as JSON lines, a file a day, and read back as conversations, trees,
/// traces and the links there are. `journal.dart` is the reading alone,
/// for where there are no files.
library;

export 'journal.dart';
export 'src/reader.dart';
export 'src/writer.dart';
