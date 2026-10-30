/// The host's words: what the app gives every guest. The host owns them
/// (`AppOwnerBase`); a guest uses them through `IAppClient`, given
/// `IAppClient` over its participant.
library;

import 'package:parlance/schema.dart';

part 'host_words.g.dart';

/// What the app gives its guests.
@Vocabulary('app')
abstract class App {
  /// Whether the app is dark now.
  @StateWord('dark')
  bool get dark;

  /// Shows a short message over everything.
  @CommandWord('toast')
  void toast({@Length(max: 80) required String text});
}
