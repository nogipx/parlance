# A house on switchboard

A small host from start to end: a house with rooms, lights, heating, a door and a doorbell. Run it:

```
fvm dart run example/main.dart
```

| File | What it shows |
|---|---|
| `house/words.dart` | The vocabulary, typed: `HouseState`, `HouseCommand`, `HouseFact` as enums, params as records, `Mode` as a Dart enum; who acts (`Who`) and who may call what (`Callers`). Every name is written here once. |
| `house/house.dart` | The owner: defines its words through `r.state()`, `r.command()`, `r.fact()`, serves the commands from its devices, writes states with the call's cause, emits facts, says when a command is unavailable, and adds a guard (`night-door`). |
| `house/links.dart` | Links built from the words (`trigger()`, `holds()`, `step()`): a reaction, a reaction with a temporary step, a binding, a constraint, an own command and an own state. |
| `main.dart` | The tour, in eight parts. |

What the tour shows:

1. **Typed calls.** `registry.command(HouseCommand.setLight).call((room: 'kitchen', on: true), by: ...)`. A guest is refused what its callers do not allow, and a room that does not exist is refused as `invalidParams`.
2. **A fact sets off a reaction.** Motion lights the hall. `explain` tells on whose behalf, through which link and by which calls.
3. **A binding.** While it is night the heating is held at 17 °C as a layer. In the morning the layer goes and the heating returns.
4. **A guard.** The door stays locked at night (`denied`, overridable). A resident overrides it.
5. **A constraint and a temporary step.** While away, unlocking is denied by a link, and no one overrides it. A guest rings: the porch light comes on for a moment, called on the guest's behalf, with the guest's rights.
6. **Own words.** `my.movie` is callable by the residents and refused to a guest. `my.guests` is a flag.
7. **A phone over remote.** A session the house opens for the phone (rpc_dart, in memory here). A typed call is made through `client.command(word)`. A `RegistryMirror` reaches the call's seq, then reads typed.
8. **An agent over MCP.** Its tools come from `switchboardTools` over a `LocalBoard`: the curated ones, plus one per command it may call. It gets no link tools, because it is not one of the residents who manage links.

`test/example_test.dart` runs the tour and holds it to what it prints.
