/// The generator that makes parlance's typed words: you do not import this
/// library. A module's vocabulary is written once as an abstract class in
/// its own package, annotated with `@Vocabulary` (which lives in
/// `package:parlance`, alongside the words, shapes and types the generated
/// code builds on); this package, run by `build_runner`, reads those
/// annotations and generates the enums of the words, their shapes, and the
/// base of the owner and the client.
///
/// To use it, add to the vocabulary package's `pubspec.yaml`:
///
/// ```yaml
/// dev_dependencies:
///   build_runner: any
///   parlance_generator: ^0.1.0
/// ```
///
/// and run `dart run build_runner build` — there is nothing to import here.
library;
