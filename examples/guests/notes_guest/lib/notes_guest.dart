/// Guest A, a notebook widlet: it owns the notes' words and knows no other
/// guest, nor the host's code. Compiled to WASM, its runtime hands it the
/// endpoint to its host; here a test or the demo does.
library;

import 'package:notes_words/notes_words.dart';
import 'package:parlance/registry.dart';
import 'package:parlance/remote.dart';
import 'package:rpc_dart/rpc_dart.dart';

/// The owner of the notes' words: its base, made from [Notes], defines
/// them; this keeps the notes and serves `notes.add`.
final class Notebook extends NotesOwner {
  final List<Note> _notes = [];
  var _next = 0;

  @override
  void sync() => all.set(List.of(_notes));

  @override
  void add(CommandCallOf<NotesAdd> call) {
    final note = (id: 'n${++_next}', text: call.params.text);
    _notes.add(note);
    all.set(List.of(_notes), cause: call.inReply);
    added(id: note.id, text: note.text, cause: call.inReply);
  }
}

/// What the guest's `main` does: joins its host over [endpoint] as the
/// participant the host serves it, and attaches its owner. Who it is and
/// who may call its commands, the host says.
Future<RemoteParticipant> startNotes(RpcPeerEndpoint endpoint) async {
  final p = await RemoteParticipant.over(endpoint);
  p.attach({'book': Notebook()});
  await p.flush();
  return p;
}
