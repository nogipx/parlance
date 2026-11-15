/// The host and its two guests in one process: the notes guest gives its
/// words, the board guest uses the app's and the notes', typed, knowing
/// neither of them but by their words packages.
///
/// Run: `fvm dart run bin/demo.dart` (in examples/guests/host).
library;

import 'package:board_guest/board_guest.dart';
import 'package:guests_host/host.dart';
import 'package:guests_host/in_memory.dart';
import 'package:notes_guest/notes_guest.dart';
import 'package:notes_words/notes_words.dart';

Future<void> main() async {
  final host = Shell();
  final notes = await loadInMemory(
    host: host,
    id: 'notes',
    vocabularies: [notesWords],
    start: startNotes,
  );
  final (board, b) = await loadInMemory(
    host: host,
    id: 'board',
    start: (e) =>
        startBoard(e, appProvider: Who.app, notesProvider: Who.widlet('notes')),
  );
  print('guests: notes as ${notes.who}, board as ${board.who}');

  await b.pin('buy milk');
  await board.settle();
  print('the board shows: ${[for (final n in b.shown) n.text]}');
  print('the app toasted: ${host.app.toasts}');

  await b.pin('call ann');
  await b.pin('milk for tomorrow');
  // Notes provides the stream; the board consumes it through the words package,
  // over two guest connections. The owner ends it after the matching notes.
  final found = await b.notes.search(text: 'milk').toList();
  print(
    'the board streamed matching notes: ${[for (final note in found) note.text]}',
  );

  host.unload('notes');
  await board.settle();
  print(
    'notes unloaded: notes.add is '
    '${INotesClient(participant: board, provider: Who.widlet('notes')).status(NotesCommand.add)}',
  );

  await b.close();
  await host.dispose();
  await closeInMemory();
}
