# Examples

## Level by level

One small domain, a player's volume, on every level. `levels/player.dart` holds its words, the `Player` owner the levels with a registry start (`startPlayer`), and a `Knob`: a part of the app that knows only the five interfaces and so runs on every level unchanged, in the host's process and across a connection.

| Run | What it shows |
|---|---|
| `dart run example/levels/level0_local.dart` | A local registry: the `Player` owner and the knob on a `LocalRegistry`, in one process, keeping nothing past what is now. The rules hold (the player's vocabulary is its own, a value out of range is refused), anyone may call its commands, a late listener still sees the value now. |
| `dart run example/levels/level1_registry.dart` | The registry: the same code, `main` making a `Registry` and saying who may call the player's commands. The player is an `Owner` on a participant `main` makes (its vocabulary, who calls its commands); the knob reads and calls through a listener's participant. A guest sees the command `notPermitted` before calling and is refused, may not define in the player's vocabulary, a value out of range is refused, `explain` tells who called and which part wrote. |
| `dart run example/levels/level3_remote.dart` | Over the network: the phone joins as a `RemoteParticipant` over an `RpcClientConnection`, acting as the principal the host gave it, and the same knob runs on it unchanged: it calls, hears the fact, and reads the state it watches. |
| `dart run example/levels/core.dart` | The bare core under both: a `LocalState`, a `LocalCommand` and a `LocalFact`, no names. The knob runs on it too, as it knows only the interfaces. |

# A house on parlance

A small host from start to end: a house with rooms, lights, heating, a door and a doorbell. Run it:

```
fvm dart run example/main.dart
```

| File | What it shows |
|---|---|
| `house/words.dart` | The vocabularies, each an abstract class: `House` (vocabulary `house`) and a `Visit`, each word a member marked `@StateWord`, `@CommandWord`, `@QueryWord` or `@FactWord`, with its bounds (`@Range`, `@ChoiceOf`), callers and whether it may be unavailable; `Mode` as a Dart enum; who acts (`Who`) and who may call what (`Callers`). Every name is written here once. |
| `house/words.g.dart` | Made by `parlance_generator` from them (`fvm dart run build_runner build`, never edited by hand): the typed words (`HouseState`, `HouseCommand`, `HouseQuery`, `HouseFact`), their params records (`HouseSetLight`), the vocabulary `houseWords` (granted to the house's participant in `main.dart`), the owner base `HouseOwnerBase` and the client `HouseClient`. |
| `house/house.dart` | The owner, `Home extends HouseOwnerBase`: code only, it says nothing of who it is or what it may. Its base defines the words and keeps what it sets (`heat = target`; keyed, `light[room] = on`), and says its facts by methods of their params (`rang(who:, by:)`, `motion(room:)`); it writes one handler per command and query, of their own params, with no cause (what it sets follows from the call), says why the door cannot be locked now (`whyNotLock`), and in its constructor keeps its rooms as a tracked kind, adds a guard (`night-door`) once attached, and follows its devices, its model: `follow(_pull, on: devices.changed)` sets what they say now. |
| `house/visit.dart` | A module beside the house, knowing it only by its words: a `GuestBook extends VisitOwnerBase` that hears the doorbell through `HouseClient` (`hear`, so what it sets follows from the ring). |
| `main.dart` | The house's participant (who it is, its vocabulary `houseWords`, who calls its commands by default, on whose behalf it speaks), its owner as the part `devices`, then the tour in seven parts; a listener of `registry.journal` from the start. |

What the tour shows:

1. **Typed calls, and why a state is so.** `ann.command(HouseCommand.setLight).call((room: 'kitchen', on: true))`, on ann's participant: `main` hands out participants, never the registry. `explain` tells who wrote the light (`house@devices`, the owner's part), the message that set it going (its `origin`: `house.light.set` by ann) and the call it was answering. A guest is refused what its callers do not allow (the heating's callers come from the participant's default), and a room that does not exist is refused as `invalidParams`. A view's `status` says, before any call, what is there for the guest: `notPermitted`, `ready`, `missing`.
2. **A guard.** At night only a resident unlocks the door: an agent is `denied`, by the house's guard, which says itself who passes.
3. **A query.** `bob.query(HouseQuery.rooms).ask((lit: true))`: a question that changes nothing, asked rather than called; asking again is safe, and the registry keeps nothing of it.
4. **By hand.** A switch flipped by hand, not through a command: the owner follows its devices (`follow(..., on: devices.changed)`), so it is synced on its own and nobody calls `sync()` on its participant.
5. **A scope.** A visit is a participant with its owner, made when guests come: its words are `ready` meanwhile; it hears the doorbell and keeps who is in, writing with a cause that names only the ring it follows, and the registry gives the write its origin (`house.doorbell.rang` by bob); disposed when they leave, its words go, and a guest's view sees `visit.guests` missing.
6. **A phone that joins over remote.** The house opens a session for the phone and says who it is; the phone joins it as a `RemoteParticipant` over an `RpcClientConnection` (in memory here, one that does not come back). It uses the house through `IHouseClient`, given `HouseClient(phone)`: it watches the states it reads (`heatChanges`), calls `setHeat(target: 22)` and reads what the call wrote as soon as the call answers; a call refused (40 °C, above the word's bound) throws `CallNotDone` with why.
7. **The journal.** Everything done, as it happened, from the listener `main` made first: the ring's conversation (the fact, the guest book's write), each entry with who did it and the message it started with. A host writes it where it lasts with `package:parlance_journal`.

`test/example_test.dart` runs the tour and holds it to what it prints.
