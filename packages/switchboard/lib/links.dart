/// Links: the user's own words and the four relations — reactions,
/// bindings, constraints and interceptions — on a registry.
///
/// See SPEC.md, §13.
library;

export 'src/links/engine.dart';
export 'src/links/expr.dart' show StateReader, evaluate, evaluateWith, resolve;
export 'src/links/model.dart';
