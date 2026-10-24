/// The registry: states, commands and facts that participants share
/// without knowing each other, layers, guards, before hooks and the feed.
///
/// The contract: skills/switchboard/references/registry.md (§1–12).
library;

export 'src/registry/cause.dart' show Principal, Cause;
export 'src/registry/descriptors.dart';
export 'src/registry/ids.dart' show newId, isValidName;
export 'src/registry/json.dart';
export 'src/registry/messages.dart';
export 'src/registry/registry.dart';
export 'src/registry/types.dart';
