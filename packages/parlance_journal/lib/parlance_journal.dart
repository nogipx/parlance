/// A registry's journal (parlance SPEC §9.3) kept where it lasts: written
/// as JSON lines, a file a day, and read back as conversations, traces and
/// the links there are.
library;

export 'src/reader.dart';
export 'src/writer.dart';
