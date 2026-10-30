/// Guest B, a board widlet: it pins notes and shows them, using the app's
/// words and the notes guest's, typed. It knows neither the host's code
/// nor the notes guest's: only their words packages, `host_words` and
/// `notes_words`.
library;

import 'dart:async';

import 'package:host_words/host_words.dart';
import 'package:notes_words/notes_words.dart';
import 'package:parlance/app.dart';
import 'package:rpc_dart/rpc_dart.dart';

/// The board: what it does, through the words' interfaces only, so a test
/// gives it stand-ins.
final class Board {
  Board(this.app, this.notes) {
    // Another's state reaches a guest while it watches it.
    _watching = notes.all.changes.listen((all) => shown = all ?? const []);
  }

  final IAppClient app;
  final INotesClient notes;
  late final StreamSubscription<List<Note>?> _watching;

  /// The notes it shows now.
  List<Note> shown = const [];

  /// Pins [text]: a note in the notes guest, a toast from the app.
  Future<void> pin(String text) async {
    await notes.add(text: text);
    await app.toast(text: 'pinned: $text');
  }

  Future<void> close() => _watching.cancel();
}

/// What the guest's `main` does: joins its host over [endpoint] and makes
/// the board over the clients of the words it uses. Whenever one of them
/// comes not as the board was built against (the notes guest updated
/// apart from it), the participant tells it itself: an error `mismatch`
/// with every break, to [onError], and in development the developer log.
Future<(IRemoteParticipant, Board)> startBoard(
  RpcPeerEndpoint endpoint, {
  void Function(ParticipantError error)? onError,
}) async {
  final p = await Host.joinEndpoint(endpoint, onError: onError);
  return (p, Board(AppClient(p), NotesClient(p)));
}
