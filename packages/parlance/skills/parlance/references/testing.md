# parlance contract: testing (§24)

Part of the contract the code and its tests follow; sections keep their numbers across these files (`SPEC §n` in the code), and SKILL.md maps them.

## 24. Testing a module

`package:parlance/testing.dart`: `TestHost`, a registry for one test, the stand-ins for the modules the test leaves out, and what happened, read back. A module is tested as it runs: through its own participant, knowing the others only by their words.

```dart
final host = TestHost();
final outside = host.standInState(WeatherState.outside, 10); // another's state
final heater = host.standInCommand(HeaterCommand.setPower);       // another's command
host.participant(me, owners: [Thermostat()]);
await host.settle();
outside.set(25);
await host.settle();
expect(heater.params, [(on: true), (on: false)]);
expect(host.written(ThermostatState.heating), [true, false]);
await host.dispose();
```

- **The module under test** gets a participant as `main` would make it, `participant(who, owners:, rights:, access:)`, or one across a connection in memory, `join(who, ...)` (a `RemoteParticipant` of a session the host accepted as `who`, its frames encoded and decoded as bytes as over a real wire), so the same test says the module works as a plugin, a guest or on a phone.
- **Stand-ins** own the words of others, each vocabulary by a participant of its own (`stand-in/water` for `water.level`), so a stand-in takes only the vocabulary of its word, another module's than the one under test: `standInCommand(word, answer:, callers:)` serves a command, keeping every call's params (`CommandStandIn.params`) and answering what `answer` gives, nothing without one, refused (`ArgumentError`) for a command that never answers nothing (anyone may call it unless `callers` say otherwise); `standInFact(word)` says a fact (`say`); `standInChoices(name, [Choice(...)])` gives the choices another module's owner would, which a `@ChoiceOf(name)` is held to (`set` changes them). A state stand-in is what an owner keeps of its own: `standInState(word, value)` a `Single<T>`, `standInKeyed(word, {key: value})` a `Keyed<T>`, set and removed by the test.
- **What happened** is read after `settle()`: `written(word, key:)` the values a state was given in order (null for a removal), `said(word)` the payloads of a fact, `callsOf(word)` the call records of a command or a query (with their causes: who called, on whose behalf), and `ticks`, `calls` whole. `errors` is what went to the registry's error sink; a test that expects none says `expect(host.errors, isEmpty)`.
- `settle()` lets what is under way come: the participants across a connection answered, owners done, ticks and call records delivered, until 20 turns of the event loop in a row bring nothing new; what waits on time (a timer, a clock) is not waited for. `dispose()` ends the connections, the sessions, the modules' participants (the last made first), then the stand-ins, so a module never sees what it reads go before it does, and the registry.
- `registry` is the registry itself, for what the host does not wrap (`explain`, `usesOf`, a guard of the test's own).
- **One way to test.** A part is tested with its real client over a `TestHost`, an owner attached to one: there are no fake clients and no owner read back unattached (what an owner says unattached no one hears).
