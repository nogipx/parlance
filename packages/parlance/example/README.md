# Examples

## Level by level

One small domain, a player's volume, on every level. `levels/player.dart` holds its words and a `Knob`: a part of the app that knows only the five interfaces and so runs on every level unchanged.

| Run | What it shows |
|---|---|
| `dart run example/levels/level0_core.dart` | The core: a `Cell`, a `Port` and a `Signal` in one process. One writer per state, a late listener still sees the value now. |
| `dart run example/levels/level1_registry.dart` | The registry: the same knob on named, typed words. A guest is refused, a value out of range is refused, `explain` tells who called and who wrote. |
| `dart run example/levels/level2_links.dart` | Links: a limiter kept as data turns the volume back when it clips; the cause names the link. |
| `dart run example/levels/level3_remote.dart` | Over the network: a phone calls and reads the same words through rpc_dart, acting as the principal the host gave it. |
| `dart run example/levels/level4_agent.dart` | An agent: the vocabulary as MCP tools; the agent learns the words from the catalog and calls one. |

# A house on parlance

A small host from start to end: a house with rooms, lights, heating, a door and a doorbell. Run it:

```
fvm dart run example/main.dart
```

| File | What it shows |
|---|---|
| `house/words.dart` | The vocabulary, typed: `HouseState`, `HouseCommand`, `HouseQuery`, `HouseFact` as enums, params as records, `Mode` as a Dart enum; who acts (`Who`) and who may call what (`Callers`). Every name is written here once. |
| `house/house.dart` | The owner, an `Owner` (`package:parlance/owners.dart`): code only, it says nothing of who it is or what it may. Keeps its rooms as a tracked kind, defines its words through its participant (`p.state()`, `p.command()`, `p.query()`, `p.fact()`), serves the commands from its devices, answers a query, writes states with the call's cause, emits facts, says when a command is unavailable, and adds a guard (`night-door`) that judges its own commands. |
| `house/links.dart` | Links built from the words (`trigger()`, `holds()`, `step()`): a reaction, a reaction with a temporary step, a binding, a constraint, an own command and an own state. |
| `main.dart` | The house's participant (who it is, its namespaces, who calls its commands by default, on whose behalf it speaks), its owner as the part `devices`, then the tour in nine parts. |

What the tour shows:

1. **Typed calls.** `registry.command(HouseCommand.setLight).call((room: 'kitchen', on: true), by: ...)`. A guest is refused what its callers do not allow (the heating's callers come from the participant's default), and a room that does not exist is refused as `invalidParams`. A view's `status` says, before any call, what is there for the guest: `notPermitted`, `ready`, `missing`.
2. **A fact sets off a reaction.** Motion lights the hall. `explain` tells on whose behalf (`house:devices`, the owner's part), through which link and by which calls.
3. **A binding.** While it is night the heating is held at 17 °C as a layer. In the morning the layer goes and the heating returns.
4. **A guard.** The door stays locked at night (`denied`, overridable). A resident overrides it.
5. **A constraint and a temporary step.** While away, unlocking is denied by a link, and no one overrides it. A guest rings: the porch light comes on for a moment, called on the guest's behalf, with the guest's rights.
6. **Own words.** `my.movie` is callable by the residents and refused to a guest. `my.guests` is a flag.
7. **A query.** `registry.query(HouseQuery.rooms).ask((lit: true), by: ...)`: a question that changes nothing, asked rather than called; asking again is safe, and the registry keeps nothing of it.
8. **A phone that joins over remote.** The house opens a session for the phone and says who it is; the phone joins it as a `RemoteParticipant` over an `RpcClientConnection` (in memory here, one that does not come back). It watches the states it reads, calls with `part.command(word).call(...)`, and reads what the call wrote as soon as the call answers.
9. **An agent over MCP.** Its tools come from `parlanceTools` over a `LocalBoard`: the curated ones, plus one per command it may call. It gets no link tools, because it is not one of the residents who manage links.

`test/example_test.dart` runs the tour and holds it to what it prints.
