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
- Typed (§18): `view.state(word).read()`, `.readAll()`, `.watch()` (now, then whenever it changes, deduplicated; a remote view keeps the state while it is listened to);
  `view.command(word).call(params)`; `view.fact(word).stream`,
  `.recent(count)`; `.status`, `.statusChanges` on each.

## LocalView(registry, by:)

Reads the registry itself, only what `by` may read (`mayRead`);
`changes` filters its ticks; calls as `by`.

## MirrorView(mirror, client)

Reads the mirror's copy. It counts who listens for which states and
facts and subscribes the mirror to their union whenever that changes:
the feed carries what screens draw and nothing else, and the host knows
what the participant hears. Calls go through the client; the call waits
until the mirror has reached the seq it answered at. `settled` completes
when the mirror has the values of what its listeners ask for now. After a lost
connection set the new `client` and `mirror.follow(client)`: the
subscription is kept.
