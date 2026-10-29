import 'package:parlance/schema.dart';

part 'notes.g.dart';

/// A notebook: how many notes it holds, and adding one.
@Vocabulary('notes')
abstract class Notes {
  /// How many notes there are.
  @StateWord()
  @Range(min: 0)
  int get count;

  /// Adds a note.
  @CommandWord(callers: Callers({'user': Access.allow, 'agent': Access.allow}))
  void add({@Length(max: 500) required String text});
}

/// The notebook's owner: it keeps the notes, the count follows.
final class Book extends NotesOwnerBase {
  Book() {
    count.set(0);
  }

  final _kept = <String>[];

  @override
  void add({required String text}) {
    _kept.add(text);
    count.set(_kept.length);
  }
}
