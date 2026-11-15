# A host and two guests

How widlet guests (Dart, compiled to WASM) and their host share words: every guest is a participant of the host's registry, and a guest uses the host's words and another guest's, typed, through their words packages alone.

| Package | What it is | Depends on |
|---|---|---|
| `host_words` | The app's words (`@Vocabulary('app')`): `app.dark`, `app.toast`. The host owns them (`AppOwnerBase`); a guest takes `IAppClient`. | parlance |
| `notes_words` | The notes guest's words (`@Vocabulary('notes')`): `notes.all`, `notes.add`, `notes.added`, `notes.search` (a stream), published beside the guest. | parlance |
| `notes_guest` | Guest A: a `Notebook extends NotesOwnerBase`, joined over the endpoint its runtime hands it (`Host.joinEndpoint`). | parlance, notes_words |
| `board_guest` | Guest B: a board that pins notes and toasts, through `IAppClient` and `INotesClient`; it says, as they come, the words not as it was built against. | parlance, host_words, notes_words |
| `host` (`guests_host`) | One host (`Host`), the app's owner, a session per guest: explicitly granted vocabularies independent of its id, its commands called by guests and the user (the host says so, not the guest). | parlance, host_words; the guests only to run them here |

What it shows (`fvm dart run bin/demo.dart` and `fvm dart test` in `host`):

1. **Typed across guests.** The board pins a note: the notes guest stores it, the board shows it (it watches `notes.all`) and hears `notes.added`, the app toasts. JSON goes on the wire; both ends have types.
2. **The host sees it all.** `explain('widlet/notes/notes.all')` on the host's registry (`host.registry`, from `tools.dart`): the notes guest's part wrote it, following the board's call.
3. **A guest of another version.** A notes guest that defines `notes.add` and `notes.all` otherwise: the board is told every difference at once (`WordMismatch`, §6.5), before it calls or reads.
4. **Guests come and go.** Started in any order; a guest unloaded takes its words, the board sees them missing; one loaded again brings them back.
5. **Boundaries.** A guest defines in its own vocabulary only; the board's and the notes guest's pubspecs name no other guest.
6. **Independent instances.** The same notes guest runs as `widlet/work` and `widlet/personal`, both granted `notesWords`. `INotesClient(participant: user, provider: Who.widlet('work'))` binds one instance; unloading it leaves the personal notes available.
7. **A data stream across guests.** `@ServerStreamWord('search') Stream<Note> search({String text = ''})` is implemented by `Notebook` as a finite stream of matching notes. The board calls `b.notes.search(text: 'milk').toList()` through its generated client: parameters and typed record elements cross both guest connections, and the owner completes the stream. An empty filter streams every note; no matches completes without elements. The board imports only the words package.

Here each guest's connection is in memory (`lib/in_memory.dart`); in widlet the host loads its WASM and hands it the endpoint, and the guest's code is the same.
