# parlance contract: testing (§24)

Part of the contract the code and its tests follow; sections keep their numbers across these files (`SPEC §n` in the code), and SKILL.md maps them.

## 24. Testing a module

`package:parlance/testing.dart`: `TestHost`, a registry for one test, the stand-ins for the modules the test leaves out, and what happened, read back. A module is tested as it runs: through its own participant, knowing the others only by their words.

```dart
final host = TestHost();
const weatherTarget = Principal('weather');
const heaterTarget = Principal('heater');
// Thermostat binds its clients to these targets.
final outside = host.standInState(WeatherState.outside, 10, target: weatherTarget);
final heater = host.standInCommand(HeaterCommand.setPower, target: heaterTarget);
host.participant(me, owners: [Thermostat()]);
await host.settle();
outside.set(25);
await host.settle();
expect(heater.params, [(on: true), (on: false)]);
expect(host.written(ThermostatState.heating, target: me), [true, false]);
await host.dispose();
```

- **The module under test** gets a participant as `main` would make it, `participant(who, owners:, rights:, access:)`, or one across a connection in memory, `join(who, ...)` (a `RemoteParticipant` of a session the host accepted as `who`, its frames encoded and decoded as bytes as over a real wire, reading the time by the test host's clock), so the same test says the module works as a plugin, a guest or on a phone.
- **Stand-ins** own the words of others, each `(target, vocabulary)` by a participant of its own (the target is explicitly supplied by the test), so a stand-in takes only the vocabulary of its word, another module's than the one under test: `standInCommand(word, target:, answer:, callers:)` serves a command, keeping every call's params (`CommandStandIn.params`) and answering what `answer` gives, nothing without one, refused (`ArgumentError`) for a command that never answers nothing (anyone may call it unless `callers` say otherwise); `standInFact(word, target:)` says a fact (`say`). A state stand-in is what an owner keeps of its own: `standInState(word, value, target:)` a `Single<T>`, `standInKeyed(word, {key: value}, target:)` a `Keyed<T>`, set and removed by the test.
- **What happened** is read after `settle()`: `written(word, target:, key:)` the values a state was given in order (null for a removal), `said(word, target:)` the payloads of a fact, `callsOf(word, target:)` the call records of commands (queries are not retained) (with their causes: who called, on whose behalf), and `ticks`, `calls` whole. `errors` is what went to the registry's error sink; a test that expects none says `expect(host.errors, isEmpty)`.
- `settle()` lets what is under way come: the participants across a connection answered, owners done, ticks and call records delivered, until 20 turns of the event loop in a row bring nothing new; what waits on time (a timer, a clock) is not waited for. `dispose()` ends the connections, the sessions, the modules' participants (the last made first), then the stand-ins, so a module never sees what it reads go before it does, and the registry.
- `registry` is the registry itself, for what the host does not wrap (`explain`, `usesOf`, a guard of the test's own).
- **One way to test.** A part is tested with its real client over a `TestHost`, an owner attached to one: there are no fake clients and no owner read back unattached (what an owner says unattached no one hears).

Observations (`written`, `said`, `callsOf`) also require `target:`. Identical words at another target never count as this instance's output.


TestHost.setAccess and clearAccess expose the same host-only policy operations for
tests. Observe registry.accessWarnings to assert actual warn admissions independently
of logs, and test both local and remote callers, revocation, regrant and queued data.
