# view (SPEC §20)

What a screen reads and calls: one interface whether the registry is in
this process or reached over remote, so the same widgets serve both.

## IRegistryView

- `read(state, {key})`, `readAll(state)`: the values now, at once (a
  screen builds from them synchronously); null or empty for what the view
  does not have or its principal may not read.
- `changes(states)`: told whenever any of those states changes, and when
  a remote view loses or finds the registry. A screen listens while it is
  shown, for exactly the states it draws.
- `facts(fact)`: the facts said from now on; `recent(fact, count)`: the
  last the registry keeps, oldest first, to start a list with.
- `call(command, params)`: on behalf of the view's one principal; a read
  after it reads what it wrote.
- `synced`: false while a remote view is cut off; what it reads is then
  the last it had, and a screen says so rather than show it as now.
- `status(word)`, `statusChanges(word)`: whether the view's principal
  can use the word now (§6.5), and each change of it; a part shows a
  missing or unavailable command for what it is rather than fail on it.
- Typed (§18): `view.state(word).read()`, `.readAll()`, `.watch()` (now, then whenever it changes, deduplicated; a remote view keeps the state while it is listened to); an old name of a word (§6.4) is told the word's changes and hears its facts, here and across a connection;
  `view.command(word).call(params)`; `view.fact(word).stream`,
  `.recent(count)`; `.status`, `.statusChanges` on each.

## LocalView(registry, by:)

Reads the registry itself, only what `by` may read (`mayRead`);
`changes` filters its ticks; calls as `by`.

## Across a connection

A `RemoteParticipant` (§22) is the view there: it keeps the states and hears the facts its listeners ask for, and no others, subscribing its session to their union whenever that changes, so the feed carries what screens draw and the host knows what it hears; a call answers once the view has reached what it wrote; after a lost connection the subscription is kept. The mirror and the client beneath are the package's.

## fetch(state)

A read by name, of a state the view may not keep: what a part naming words at run time reads (a plugin, an agent). In this process it is `readAll`, counted as a use (§6.8); across a connection the view answers once it has the state and, with `keep` (the default), keeps it from then on; `keep: false` lets it go again, for a look at many states (an agent reading all). What changes in one turn of the event loop is one subscription. One it may not read is empty.
