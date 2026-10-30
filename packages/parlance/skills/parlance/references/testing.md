# parlance contract: testing (§24)

Part of the contract the code and its tests follow; sections keep their numbers across these files (`SPEC §n` in the code), and SKILL.md maps them.

## 24. Testing a module

`package:parlance/testing.dart`: `TestHost`, a registry for one test, the stand-ins for the modules the test leaves out, and what happened, read back. A module is tested as it runs: through its own participant, knowing the others only by their words.

```dart
final host = TestHost();
final outside = host.stateOf(WeatherState.outside, 10); // another's state
final heater = host.commandOf(HeaterCommand.power);       // another's command
host.participant(me, owners: [Thermostat()]);
await host.settle();
outside.set(25);
await host.settle();
expect(heater.params, [(on: true), (on: false)]);
expect(host.written(ThermostatState.heating), [true, false]);
await host.dispose();
```

- **The module under test** gets a participant as `main` would make it, `participant(who, owners:, rights:, access:)`, or one across a connection in memory, `join(who, ...)` (a `RemoteParticipant` of a session the host accepted as `who`, its frames encoded and decoded as bytes as over a real wire), so the same test says the module works as a plugin, a guest or on a phone.
- **Stand-ins** own the words of others, each vocabulary by a participant of its own (`stand-in/water` for `water.level`), so a stand-in takes only the vocabulary of its word, another module's than the one under test: `stateOf(word, value)` holds a value and gives the writer to change it; `commandOf(word, answer:, callers:)` serves a command, keeping every call's params (`Stub.params`) and answering what `answer` gives (anyone may call it unless `callers` say otherwise); `factOf(word)` says a fact.
- **What happened** is read after `settle()`: `written(word, key:)` the values a state was given in order (null for a removal), `said(word)` the payloads of a fact, `callsOf(name)` the call records of a command (with their causes: who called, on whose behalf), and `ticks`, `calls` whole. `errors` is what went to the registry's error sink; a test that expects none says `expect(host.errors, isEmpty)`.
- `settle()` lets what is under way come: the participants across a connection answered, ticks and call records delivered. `dispose()` ends the connections, the sessions, the stand-ins and the registry.
- `registry` is the registry itself, for what the host does not wrap (`explain`, `usesOf`, a guard of the test's own).
