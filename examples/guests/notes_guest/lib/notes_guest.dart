/// Guest A, a notebook widlet: it owns the notes' words and knows no other
/// guest, nor the host's code. Compiled to WASM, its runtime hands it the
/// endpoint to its host; here a test or the demo does.
library;

import 'package:notes_words/notes_words.dart';
import 'package:parlance/app.dart';
import 'package:rpc_dart/rpc_dart.dart';

/// The owner of the notes' words: its base, made from [Notes], defines
/// them and keeps the notes it set; this serves `notes.add`.
final class Notebook extends NotesOwnerBase {
  Notebook() {
    all.set(const []);
  }

  var _next = 0;

  @override
  void add({required String text}) {
    final note = (id: 'n${++_next}', text: text);
    all.set([...?all.value, note]);
    added.say(id: note.id, text: note.text);
  }
}

/// What the guest's `main` does: joins its host over [endpoint] as the
/// participant the host serves it, and attaches its owner. Who it is and
/// who may call its commands, the host says.
Future<IRemoteParticipant> startNotes(RpcPeerEndpoint endpoint) async {
  final p = await Host.joinEndpoint(endpoint);
  await p.attach([Notebook()]);
  return p;
}
