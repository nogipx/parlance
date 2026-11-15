# A house on parlance

A small host from start to end: a house with rooms, lights, heating, a door and a doorbell. Run it:

```
fvm dart run example/main.dart
```

| File | What it shows |
|---|---|
| `house/words.dart` | The vocabularies, each an abstract class: `House` (vocabulary `house`) and a `Visit`, each word a member marked `@StateWord`, `@CommandWord`, `@QueryWord`, `@FactWord` or `@ServerStreamWord`, with its bounds (`@Range`, `@Length`), callers/readers and whether it may be unavailable; `Mode` as a Dart enum; who acts (`Who`) and who may call what (`Callers`). Every name is written here once. |
| `house/words.g.dart` | Made by `parlance_generator` from them (`fvm dart run build_runner build`, never edited by hand): the typed words (`HouseState`, `HouseCommand`, `HouseQuery`, `HouseFact`, `HouseServerStream`), their params records (`HouseSetLight`), the vocabulary `houseWords` (granted to the house's participant in `main.dart`), the owner base `HouseOwnerBase` and the client `IHouseClient`. |
| `house/house.dart` | The owner, `Home extends HouseOwnerBase`: code only, it says nothing of who it is or what it may. Its base defines the words and keeps what it sets (`heat.set(target)`; keyed, `light.set(room, on)`), and says its facts by `say` with their params (`rang.say(who:, by:)`, `motion.say(room:)`); it writes one handler per command and query, of their own params, with no cause (what it sets follows from the call), says why the door cannot be locked now (`whyNotLock`), and validates room IDs in its handlers, removes stale light keys when following its model, adds a guard (`night-door`) once attached, and follows its devices, its model: `follow(pull: _pull, on: devices.changed)` sets what they say now. |
| `house/visit.dart` | A module beside the house, knowing it only by its words: a `GuestBook extends VisitOwnerBase` that hears the doorbell through its client, `hear(fact: IHouseClient.of(owner: this, target: houseTarget).rang, onData: ...)` in its constructor, so what it sets follows from the ring. |
| `main.dart` | The house's participant (who it is, its vocabulary `houseWords`, who calls its commands by default, on whose behalf it speaks), then the tour in eight parts; a listener of `registry.journal` from the start. |

What the tour shows:

1. **Typed calls, and why a state is so.** `ann.setLight(room: 'kitchen', on: true)`, through the client of ann's participant: `main` hands out participants, never the registry. `explain` tells who wrote the light (`home@house`, the owner's part, named by its vocabulary), the message that set it going (its `origin`: `home/house.set_light` by ann) and the call it was answering. A guest is refused what its callers do not allow (the heating's callers come from the participant's default), and the owner answers a room that does not exist as `failed`, with `no room attic`. A view's `status` says, before any call, what is there for the guest: `notPermitted`, `ready`, `missing`.
2. **A guard.** At night only a resident unlocks the door: an agent is `denied`, by the house's guard, which says itself who passes.
3. **A query.** `bob.rooms(lit: true)`: a question that changes nothing; asking again is safe, and the registry keeps nothing of it.
4. **Data streams.** `temperatureHistory(room: 'kitchen').toList()` consumes a finite snapshot of the device's readings, `[20, 21, 22]`. The owner returns `Stream<num>`; the history belongs to its model. Parlance keeps no history or last element for this word.
5. **By hand.** A switch flipped by hand, not through a command: the owner follows its devices (`follow(pull: ..., on: devices.changed)`), so it is synced on its own and nobody calls `sync()` on its participant.
6. **A scope.** A visit is a participant with its owner, made when guests come: its words are `ready` meanwhile; it hears the doorbell and keeps who is in, writing with a cause that names only the ring it follows, and the registry gives the write its origin (`home/house.rang` by bob); disposed when they leave, its words go, and a guest's view sees `visit.guests` missing.
7. **A phone that joins over remote.** The house opens a session for the phone and says who it is; the phone joins it with `Host.join` over an `RpcClientConnection` (in memory here, one that does not come back). It uses the house through `IHouseClient`: watches states, calls `setHeat(target: 22)`, then opens `temperatureSamples(room: 'kitchen')` with `StreamIterator`. It reads the initial temperature and a new measurement, and explicitly cancels. The owner follows one shared sensor source, with an initial reading per subscriber; cancelling removes only that subscription. A refused command (40 °C, above the word's bound) throws `CallNotDone` with why.
8. **The journal.** Everything done, as it happened, from the listener `main` made first: the ring's conversation (the fact, the guest book's write), each entry with who did it and the message it started with. Stream elements do not become journal entries. A host writes it where it lasts with `package:parlance_journal`.

`test/example_test.dart` runs the tour and holds it to what it prints.

## Three streaming interactions

Run `fvm dart run example/streams.dart`. The client connects through RPC to a
local document owner. The vocabulary is in `streams/words.dart`:

```dart
@ServerStreamWord('read')
Stream<String> read({required String name});

@ClientStreamWord('save', callers: Callers.anyone)
Future<int> save(Stream<String> lines, {required String name});

@BidiStreamWord('preview', callers: Callers.anyone)
Stream<String> preview(Stream<String> lines, {String prefix = ''});
```

The generated client keeps these signatures, adding `cancel:`. `save` starts
immediately; `read` and `preview` start when listened to. `preview` emits one
response per incoming line, then a final response after its input closes.
Cancelling the output or token closes both directions. A `Future<void>` client
stream can acknowledge completion without returning application data.

The API intentionally has no mode flags or explicit session identifiers.
`server` means the word's owner, regardless of which process hosts it.


Run fvm dart run example/access.dart for runtime host access overrides: a guest
invokes an annotated warn command, the host restricts it, then restores the policy
without recreating the owner. Structured warnings identify the exact caller and word.
