# Examples

## Level by level

One small domain, a player's volume, on every level. `levels/player.dart` holds its words, the `Player` owner the levels with a registry start (`startPlayer`), and a `Knob`: a part of the app that knows only the five interfaces and so runs on every level unchanged, in the host's process and across a connection.

| Run | What it shows |
|---|---|
| `dart run example/levels/level0_core.dart` | The core: a `Cell`, a `Port` and a `Signal` in one process. One writer per state, a late listener still sees the value now. |
| `dart run example/levels/level1_registry.dart` | The registry: the same knob on named, typed words. The player is an `Owner` on a participant `main` makes (its namespace, who calls its commands); the knob reads and calls through a listener's participant. A guest sees the command `notPermitted` before calling and is refused, may not define in the player's namespace, a value out of range is refused, `explain` tells who called and which part wrote. |
| `dart run example/levels/level2_links.dart` | Links: a limiter kept as data turns the volume back when it clips; the cause names the link. |
| `dart run example/levels/level3_remote.dart` | Over the network: the phone joins as a `RemoteParticipant` over an `RpcClientConnection`, acting as the principal the host gave it, and the same knob runs on it unchanged: it calls, hears the fact, and reads the state it watches. |
| `dart run example/levels/level4_agent.dart` | An agent: the vocabulary as MCP tools; the agent learns the words from the catalog and calls one. |

# A house on parlance

A small host from start to end: a house with rooms, lights, heating, a door and a doorbell. Run it:

```
fvm dart run example/main.dart
```

| File | What it shows |
|---|---|
| `house/words.dart` | The vocabularies, each an abstract class: `House` (namespace `house`), a `Visit` and a `Weather` station's, each word a member marked `@StateWord`, `@CommandWord`, `@QueryWord` or `@FactWord`, with its bounds (`@Range`, `@Ref`), callers, the state a command sets and whether it may be unavailable; `Mode` as a Dart enum; who acts (`Who`) and who may call what (`Callers`). Every name is written here once. |
| `house/words.g.dart` | Made by `parlance_generator` from them (`fvm dart run build_runner build`, never edited by hand): the typed words (`HouseState`, `HouseCommand`, `HouseQuery`, `HouseFact`), their params records (`HouseSetLight`), the vocabulary `houseWords` (granted to the house's participant in `main.dart`), the owner base `HouseOwner` and the client `HouseClient`. |
| `house/house.dart` | The owner, `Home extends HouseOwner`: code only, it says nothing of who it is or what it may. Its base defines the words, keeps their writers (`light.set`, `heat.set`) and says its facts by methods of their params (`rang(who:)`, `motion(room:)`); it writes one handler per command and query, writing with `cause: call.inReply`, says why the door cannot be locked now (`whyNotLock`), keeps its rooms as a tracked kind and adds a guard (`night-door`) in `defineMore`, says where its devices' changes come from (`changes`), and writes what it has now in `sync`. |
| `house/visit.dart` | Two modules beside the house, knowing it only by its words: a `GuestBook extends VisitOwner` that says the house's words it needs (`uses`) and hears the doorbell through `HouseClient`, and a `Sprinkler` that needs a weather station's word the house does not have. |
| `house/links.dart` | Links built from the words (`trigger()`, `holds()`, `step()`): a reaction, a reaction with a temporary step, a binding, a constraint, an own command and an own state. |
| `main.dart` | The house's participant (who it is, its vocabulary `houseWords`, who calls its commands by default, on whose behalf it speaks), its owner as the part `devices`, then the tour in eleven parts. |

What the tour shows:

1. **Typed calls.** `registry.command(HouseCommand.setLight).call((room: 'kitchen', on: true), by: ...)`. A guest is refused what its callers do not allow (the heating's callers come from the participant's default), and a room that does not exist is refused as `invalidParams`. A view's `status` says, before any call, what is there for the guest: `notPermitted`, `ready`, `missing`.
2. **A fact sets off a reaction.** Motion lights the hall. `explain` tells on whose behalf (`house:devices`, the owner's part), through which link and by which calls.
3. **A binding.** While it is night the heating is held at 17 °C as a layer. In the morning the layer goes and the heating returns.
4. **A guard.** The door stays locked at night (`denied`, overridable). A resident overrides it.
5. **A constraint and a temporary step.** While away, unlocking is denied by a link, and no one overrides it. A guest rings: the porch light comes on for a moment, called on the guest's behalf, with the guest's rights.
6. **Own words.** `my.movie` is callable by the residents and refused to a guest. `my.guests` is a flag.
7. **A query.** `registry.query(HouseQuery.rooms).ask((lit: true), by: ...)`: a question that changes nothing, asked rather than called; asking again is safe, and the registry keeps nothing of it.
8. **By hand.** A switch flipped by hand, not through a command: the owner said where its devices' changes come from (`changes`), so it is synced on its own and nobody calls `sync()` on its participant.
9. **What modules need, and a scope.** A garden needs `weather.rain`, which the house has not: `checkUses()` says so at start (`module:garden/sprinkler needs weather.rain: missing`). A visit is a group of owners made when guests come: it says what it owns and uses (`registry.declarations`, `describe`), hears the doorbell and keeps who is in; disposed when they leave, its words go, and a guest's view sees `visit.guests` missing.
10. **A phone that joins over remote.** The house opens a session for the phone and says who it is; the phone joins it as a `RemoteParticipant` over an `RpcClientConnection` (in memory here, one that does not come back). It uses the house through `HouseClient(phone)`: it watches the states it reads (`heatChanges`), calls `setHeat(target: 22)` and reads what the call wrote as soon as the call answers; a call refused (40 °C, above the word's bound) throws `CallNotDone` with why.
11. **An agent over MCP.** Its tools come from `parlanceTools` over a `LocalBoard`: the curated ones, plus one per command it may call. It gets no link tools, because it is not one of the residents who manage links.

`test/example_test.dart` runs the tour and holds it to what it prints.
