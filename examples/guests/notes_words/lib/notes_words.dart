/// The notes guest's words, published beside the guest: the notes guest
/// owns them (`NotesBase`); another guest that uses them depends on this
/// package alone and takes `INotesClient`.
library;

import 'package:parlance/schema.dart';

part 'notes_words.g.dart';

/// A note: its id and its text.
typedef Note = ({String id, String text});

/// What the notes guest gives.
@Vocabulary('notes')
abstract class Notes {
  /// Every note, the newest last.
  @StateWord()
  List<Note> get all;

  /// Adds a note.
  @CommandWord()
  void add({@Length(max: 200) required String text});

  /// A note was added.
  @FactWord()
  void added({required String id, required String text});
}
