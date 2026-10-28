# A host and two guests

How widlet guests (Dart, compiled to WASM) and their host share words: every guest is a participant of the host's registry, and a guest uses the host's words and another guest's, typed, through their words packages alone.

| Package | What it is | Depends on |
|---|---|---|
| `host_words` | The app's words (`@Vocabulary('app')`): `app.dark`, `app.toast`. The host owns them (`AppOwner`); a guest takes `IAppClient`. | parlance |
| `notes_words` | The notes guest's words (`@Vocabulary('notes')`): `notes.all`, `notes.add`, `notes.added`, published beside the guest. | parlance |
| `notes_guest` | Guest A: a `Notebook extends NotesOwner`, joined over the endpoint its runtime hands it (`RemoteParticipant.over`). | parlance, notes_words |
| `board_guest` | Guest B: a board that pins notes and toasts, through `IAppClient` and `INotesClient`; it says, as they come, the words not as it was built against. | parlance, host_words, notes_words |
| `host` (`guests_host`) | One registry, the app's owner, a session per guest: its words in the vocabulary of its id, its commands called by guests and the user (the host says so, not the guest). | parlance, host_words; the guests only to run them here |

What it shows (`fvm dart run bin/demo.dart` and `fvm dart test` in `host`):

1. **Typed across guests.** The board pins a note: the notes guest stores it, the board shows it (it watches `notes.all`) and hears `notes.added`, the app toasts. JSON goes on the wire; both ends have types.
2. **The host sees it all.** `explain('notes.all')` on the host's registry: the notes guest's part wrote it, following the board's call.
3. **A guest of another version.** A notes guest that defines `notes.add` and `notes.all` otherwise: the board is told every difference at once (`WordMismatch`, §6.5), before it calls or reads.
4. **Guests come and go.** Started in any order; a guest unloaded takes its words, the board sees them missing; one loaded again brings them back.
5. **Boundaries.** A guest defines in its own vocabulary only; the board's and the notes guest's pubspecs name no other guest.

Here each guest's connection is in memory (`lib/in_memory.dart`); in widlet the host loads its WASM and hands it the endpoint, and the guest's code is the same.
