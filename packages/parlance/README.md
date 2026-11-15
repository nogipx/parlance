# parlance

**A shared language for the parts of an app that should not know each other.**

A screen, a heating module, a plugin, a phone on the network, an AI agent. Keeping such parts apart is nothing new: interfaces, dependency injection, an event bus. But each of those draws the line its own way, pair by pair, and leaves the rest to every team: who owns a value, who may change it, why it changed, how a part outside the process joins in.

parlance draws the line once, as a language. Each part uses a common vocabulary and an explicit provider principal, and ownership, rights and causes come with the language rather than with each pair. *Parlance* is the way of speaking used in a particular place; here, the place is your app.

## Providers

A word is addressed by its exact provider and portable name:
`module/work/notes.add` and `module/personal/notes.add` are independent operations.
Both instances use the same vocabulary and implementation. One principal may own
several vocabularies; one `(principal, vocabulary)` has one active owner.

```dart
final client = IHouseClient(participant: viewer, provider: houseProvider);
// Inside an owner, resolve its calling participant after attachment:
final dependency = IHouseClient.of(owner: this, provider: houseProvider);
```

`participant` is who calls; `provider` is the chosen receiver. Clients can be
bound before the provider appears. A missing provider is reported as missing;
there is no automatic fallback or broadcast. `participant.providers(vocabulary:
houseWords)` discovers actual publications, and `providerChanges` observes them.
Discovery reports permissions, availability and contract compatibility for each
published word; the application selects its dependency explicitly.

Raw tools use `WordAddress(provider, 'house.light').toString()`. Catalog entries,
subscriptions, events, streams, diagnostics and the journal use that same full
address. `module` and `module/work` are separate targets; the existing `module`
ACL selector still covers both. Remote participants require the `providers`
protocol feature. The old unscoped client API is intentionally removed.

## Runtime access

Annotations declare the initial policy. The host can override one exact word
without recreating its owner or losing its state:

```dart
final address = WordAddress(houseProvider, HouseCommand.setLight.name);
host.setAccess(
  address: address,
  access: WordAccess(callers: Callers.only(['resident'])),
);
host.clearAccess(address: address); // restore the declared policy
```

A non-null override replaces the whole selector map; null inherits the declaration.
Overrides can precede publication and survive reconnect of the same provider.
Revocation updates statuses and discovery, clears inaccessible mirror values and
stops active data streams. State/fact listeners keep their desired subscription;
regrant refreshes states and resumes facts without replay.

Access.warn permits an interaction and reports an unexpected dependency to the
developer through logs and host.registry.accessWarnings. It does not request user
confirmation. Inspection is silent; stream elements do not warn individually.
See [the runnable example](example/access.dart).

## The words

A vocabulary is made of **words**: a name and a type. There are seven kinds, like parts of speech:

| Kind | Means | Example | You |
| --- | --- | --- | --- |
| **state** | what is so now | `house.heat`, `house.light` | read and watch it; only its owner writes it |
| **command** | a request to do something | `house.set_light`, `house.lock` | call it; exactly one handler answers |
| **query** | a question that changes nothing | `orders.page`, `catalog.search` | ask it, again if need be; nothing of it is kept |
| **fact** | what happened | `house.rang`, `house.motion` | hear it; nothing is kept after it is said |
| **serverStream** | parameters → output sequence | `sensor.samples` | consume until it ends or you cancel |
| **clientStream** | input sequence → result | `documents.save` | send input, await completion |
| **bidiStream** | input sequence ↔ output sequence | `documents.preview` | send and receive within one operation |

A **query** is a command that only answers: a question by params that no state holds. It changes nothing, so it is safe to ask again, and the registry keeps nothing of it.

| | command | query |
| --- | --- | --- |
| does | changes something: writes, says, calls | only answers |
| asked again with its id | answers the first result, runs once | runs again |
| call record (journal, `explain`) | kept | none: its answers take no memory |
| who may, by default | must be said | as who may read |
| to an agent | an action | safe to ask |
| a write, a fact, a command from its handler | done | refused: the query fails, nothing changed |
| in Dart | `ICommandWord`, `.call(params)` | `IQueryWord`, `.ask(params)` |

A **keyed state** holds one value per ID under a stable word: `house.light`
has a value for each room. Owners set and remove keys explicitly; clients read
and watch individual keys or the whole state. Domain entity lists, labels and
metadata are ordinary states or queries. Owners validate ID existence in their
handlers; static alternatives use enums.

Many consumers of one value that changes: a state. One asker's answer to its own params: a query. Anything that changes the world: a command.

A **serverStream** is a lazy `Stream<T>` provided by its owner on each subscription.
The owner decides whether to share a source or create separate work. It may be
finite or continuous; Parlance keeps no last element or history, and does not
retry after a connection loss. Errors are terminal `StreamFailure`s with stable
codes. Cancellation reaches the source subscription; paused consumers have a
bounded queue and overflow fails explicitly. `HostLimits.streams` and
`SessionLimits.streams` configure `StreamLimits` (subscription count, pending
items/bytes and element size). Reopening can repeat work and cost.

Client and bidi streams take one required positional `Stream<T>` plus named
parameters. They use `callers`; server streams use `readers`. A client stream
starts on invocation and returns `Future<R>` (or `Future<void>`); server and
bidi streams start on listening. Input completion leaves output open; errors,
cancellation or final output completion end the whole operation. The three
kinds are distinct in schemas and compatibility checks, with no direction flag.
See the runnable [document example](example/streams.dart).

Host tools (`package:parlance/tools.dart`) can inspect
`host.registry.activeStreams` and subscribe to `host.registry.streamEvents`.
Immutable snapshots show the caller, cause, kind, elapsed time, separate
input/output counts, queue sizes and pause/half-close flags. Lifecycle events
distinguish completion, cancellation, failure and rejected admission. Diagnostics
retain no payloads or history; each event listener has a bounded queue. With a
host logger, each admitted operation also has a span in the existing causal
trace, without logging parameters or element contents. Byte counts are estimates
of JSON size, rather than transport traffic.

```dart
@Vocabulary('sensor')
abstract class Sensor {
  @ServerStreamWord('samples')
  Stream<int> samples({required String device});
}
```

The generated owner implements `samples`, returning its own `Stream<int>`.
The client uses `client.samples(device: 'outdoor').listen(...)` and cancels the
returned subscription, or supplies `cancel: token`. The source starts on
`listen`, after access and parameter checks. Binary media and agent consumption
through MCP are separate features. The complete contract is
[stream words](skills/parlance-core/references/streams.md).

Every word has an **owner**, the part that defined it. Nobody changes someone else's state: you ask its owner with a command, and the owner decides what to write. A command says nothing of which states its handler writes; what it wrote is told after, by causes.

Around the words:

- **Who speaks.** Every write and call is made by a principal (`resident/ann`, `module/visit`, `guest/bob`), and every command says who may call it. A refusal says why: not permitted, unavailable now, denied by a guard.
- **Why it is so.** Every change carries its cause: who acted and the call it answered. The same causes make the traces: with a log, every call is a span, the calls it led to its children, across the network too. `explain('house.light')` answers *"the house's devices wrote it, answering `house.set_light` that ann called"*.
- **Words are a public API.** Plugins, agents and the calls a host stores name them, so a renamed word keeps its old name as an alias and nothing that named it breaks.

## One way, small or large

| Piece | Library | What it is |
| --- | --- | --- |
| words | `schema.dart` | A vocabulary written once as an abstract class (`@Vocabulary`); the generator makes its typed words, the base of its owner and its client. What an owner and a part that uses the words see. |
| a host | `app.dart` | What `main` does: a `Host` makes the participants of the app's parts and serves them across connections; another process joins with `Host.join`. A small app is the same `Host` with `HostLimits.light`, keeping nothing past what is now. |
| a test | `testing.dart` | `TestHost`: a `Host` for a test, stand-ins for the modules it leaves out, what happened read back. |
| tools | `tools.dart` | The registry underneath, for tools: a journal, an inspector, a host of guests in another language. Not frozen. |
| agents | the package `parlance_mcp` and its binary `parlance-mcp` | Curated MCP tools, so an AI agent speaks the vocabulary too. |

An owner and the parts that use its words do not know where they run: in the host's process and across a connection they are given the same `IParticipant`.

## In short

One way for every part to say what it has, what it can be asked and what happened to it, whether it sits in the same process, across the network or in an agent, and one record of who asked, whether they were allowed, and why the world is as it is now.

- A whole host in miniature: [`example/`](example/) (`dart run example/main.dart`).
- The contract the code follows, section by section: [`skills/parlance-core/references/`](skills/parlance-core/references/).
