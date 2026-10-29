import 'package:parlance/schema.dart';

part 'board.g.dart';

enum Level { info, warning }

/// A note on the board: records a word carries, their fields annotated in
/// the typedef.
typedef Note = ({
  Level level,
  @Describe('What it says.') @Length(max: 200) String text,
  @Default(<String>[]) List<String> tags,
  @FieldName('by') String? author,
  Action? action,
});

typedef Action = ({
  String call,
  @Default(<String, Object?>{}) Map<String, Object?> params,
});

/// A board: the words this generator learnt beyond `Player`'s.
@Vocabulary('note', kinds: ['note'])
abstract class Board {
  /// The notes up, by id: a word named as its vocabulary.
  @StateWord(name: '', key: 'note')
  Note get notes;

  /// Anything at all.
  @StateWord()
  Object? get anything;

  /// Puts a note up; answers its id.
  @CommandWord()
  ({String id}) put({
    @Describe('Its id; else a new one.') String? id,
    required Note note,
  });

  /// Takes a note down after a while.
  @CommandWord()
  void expire({
    @ChoiceOf('note') required String id,
    @FieldName('in') @Millis(max: 60000) required int ms,
  });

  /// Pins some notes: `@ChoiceOf` on a list names its items.
  @CommandWord()
  void pin({@ChoiceOf('note') @Length(max: 3) required List<String> ids});

  /// How many read it; null when no one knows.
  @CommandWord()
  void count({required int? readers});

  /// Said by anyone: an open fact.
  @FactWord(open: true)
  void seen(Note note);
}
