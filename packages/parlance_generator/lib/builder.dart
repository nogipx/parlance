import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

import 'src/generator.dart';

/// Makes a module's typed words from its `@Vocabulary` class, into the
/// library's `.g.dart` part (beside json_serializable's).
Builder parlanceBuilder(BuilderOptions options) =>
    SharedPartBuilder([const VocabularyGenerator()], 'parlance');
