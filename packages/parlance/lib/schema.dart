/// A module's words written once as an abstract Dart class, for
/// `parlance_generator` to make their typed enums and shapes; and the
/// schema a module keeps so its published words do not change by
/// accident. It exports what the generated code names (registry,
/// participant, view), so a module's words import only it.
///
/// The contract: skills/parlance/references/schema.md (§23).
library;

export 'participant.dart';
export 'registry.dart';
export 'src/schema/annotations.dart';
export 'src/schema/schema.dart';
export 'view.dart';
