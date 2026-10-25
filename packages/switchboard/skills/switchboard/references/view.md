# view (SPEC §20)

What a screen reads and calls: one interface whether the registry is in
this process or reached over remote, so the same widgets serve both.

## RegistryView

- `read(state, {key})`, `readAll(state)`: the values now, at once (a
  screen builds from them synchronously); null or empty for what the view
  does not have or its principal may not read.
- `changes(states)`: told whenever any of those states changes, and when
  a remote view loses or finds the registry. A screen listens while it is
  shown, for exactly the states it draws.
- `facts(fact)`: the facts said from now on.
- `call(command, params)`: on behalf of the view's one principal; a read
  after it reads what it wrote.
- `synced`: false while a remote view is cut off; what it reads is then
  the last it had, and a screen says so rather than show it as now.
- Typed (§18): `view.state(word).read()`, `.readAll()`;
  `view.command(word).call(params)`; `view.fact(word).stream`.

## LocalView(registry, by:)

Reads the registry itself, only what `by` may read (`mayRead`);
`changes` filters its ticks; calls as `by`.

## MirrorView(mirror, client)

Reads the mirror's copy. It counts who listens for which states and
facts and subscribes the mirror to their union whenever that changes:
the feed carries what screens draw and nothing else, and the host knows
what the participant hears. Calls go through the client; the call waits
until the mirror has reached the seq it answered at. After a lost
connection set the new `client` and `mirror.follow(client)`: the
subscription is kept.
