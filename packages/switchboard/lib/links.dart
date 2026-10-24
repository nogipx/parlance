/// Links: the user's own words and the four relations — reactions,
/// bindings, constraints and interceptions — on a registry.
///
/// The contract: skills/switchboard/references/links.md (§13, §15).
library;

export 'src/link_words.dart';
export 'src/links/engine.dart';
export 'src/links/expr.dart' show StateReader, evaluate, evaluateWith, resolve;
export 'src/links/model.dart';
export 'src/links/typed.dart';
