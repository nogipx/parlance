# parlance contract: compatibility of words (§25)

Part of the contract the code and its tests follow; sections keep their numbers across these files (`SPEC §n` in the code), and SKILL.md maps them. This section gathers what the others say of one question: a module built against words meets them as another module defines them now; do they still agree? Each piece is specified where it lives (§6.5, §6.9, §14, §23.3); here is how they make one scheme.

## 25. Compatibility of words

Inside one build the compiler answers the question: a word changed is code that no longer compiles. What it cannot see is a module built apart: a guest updated over the air, a plugin, a peer across a connection, a host behind its guests, a call stored before a release. For them a published word is a promise, and parlance holds every word to it by one rule, in four places.

### 25.1 One rule, as the data goes

The rule judges a word's schema entry as code was built against it (§23.3: its kind, its types, its key) against the entry of the word as defined now (`entryBreaks(built, live)`, `keepsPromises`). It asks what Avro's schema resolution asks: can the reader read all the writer may write? Which side reads is the word's kind, seen from code that uses the word: it **reads** a state's values, a fact's payloads and an answer, and **gives** a command's and a query's params, which the registry reads.

| Change | In what code reads (a state, a fact, an answer) | In what code gives (params) |
|---|---|---|
| a field added | keeps: code skips a field it does not know | keeps if it may be left out; one that must be given breaks |
| a field gone | keeps if code may do without it (optional, or a default its decoder fills); else breaks | breaks: the registry refuses a field it does not know (but see §25.5) |
| a bound narrowed (`max` 100 to 50) | keeps | breaks for the values past it |
| a bound widened | breaks for the values past the old one | keeps |
| an enum value added | breaks when that value comes, unless code has a fallback for it (§25.2) | keeps |
| an enum value gone | keeps | breaks when code gives it |
| `int` where `num` was, or `num` where `int` | an integer reads where a number is read; a number where an integer is read breaks | the other way round |
| made nullable / made sure | nullable breaks; sure keeps | the other way round |
| a variant of a `oneOf` added / gone | as an enum value, a fallback too | as an enum value |
| the type changed otherwise, the kind of word, the key | breaks | breaks |
| an answer gone (the command answers nothing now) | breaks, unless code takes no answer as one (nullable) | |

Each break is a `WordBreak`: where (`path`, into the schema entry: `type.max`, `params.fields.fade`), what kind of promise (`BreakKind`: `word`, `type`, `bound`, `field`, `value`), what code was built against (`was`) and what the word says now (`now`, `is` in JSON), and whether every use meets it (`certain`): a type changed, a field gone that is needed, a field that must be given; or only some values do (a bound moved, an enum value added, a field that may be left out), and a part may never meet it. It reads `path: was …, is …` (`type.max: was 100, is 150`). Every break is said at once; under a type that changed nothing more is said of it, its bounds meaning nothing then.

The rule follows what parlance's decoders do, so it never promises more than they keep: a record's decoder skips a field it does not know and fills a missing one with its default or null; an enum's reads a value it does not know as its fallback, and with none it is an `UnknownValue`, a variant's alike; the registry checks params by their type, refusing a field it does not know, or a value, whatever fallback the owner's own code has, and filling a default.

Not in a schema, and so not judged by it: who may read or call a word (its status says that, `WordNotPermitted`, §6.5), descriptions, and what a word means. A state that held seconds and holds milliseconds, a command that does more than it did, a fact said at another moment: the same schema, another promise. A bound narrowed keeps the type's promise and may still break a screen that drew a scale to the old one. Changing meaning is changing the word, by the rule of §25.2; only a contract test sees it.

### 25.2 What may change, and how

- **A published word only changes as the rule lets.** A new word; a field added to what code reads; a param a caller may leave out; a bound narrowed on what code reads, widened on what it gives; an enum value added to what code gives.
- **A value added to what code reads keeps for code that has a fallback for it**, as Avro's reader takes its enum's default: one value of an enum marked `@Fallback()` (`EnumShape(values, unknown:)`, `EnumType.unknown`), and for a `UnionShape` an `unknown:` that makes a value from the JSON, tag and all (a subtype kept for it, holding it). The fallback is in the schema, so its fingerprint, and the rule holds it: an enum value or a variant added to what such code reads is no break. It must be in the words the code was built against, so it comes before the value it is for: a vocabulary whose enums may grow gives them one from its first release. Code with none is not stopped either: a typed read of such a value gives none (a state reads null, a fact is not heard, an answer fails), a remote participant tells it once on `errors` (`unknownValue`), and its JSON is still there to read by name. Code that writes the fallback back writes over what it did not know. A class decoded by its own `fromJson` (`JsonShape`, json_serializable's or freezed's) decodes its enums itself: its fallback is its own (`@JsonKey(unknownEnumValue:)`), the rule does not see it, and what it throws is not an `UnknownValue`.
- **A break is a new word beside the old** (`audio.volume.v2`, §1): the owner serves both, the old one often as a shim over the new, until no part uses the old one.
- **A rename is an old name** (`alias`, §6.4): parts built against the old name go on, and its use is counted under it.
- **A word goes when nothing uses it.** `usesOf(name)` (§6.8) says who still calls, reads or listens to it from outside the build; what parts were built against (§25.4) says who still holds it. A word nobody shows to have gone is kept: it costs little.
- **Before the first release nothing is promised**: a vocabulary changes freely until a version of it is out.

### 25.3 Before release: against what is out

The author of a vocabulary compares the words now with the words as released. `schemaOf(words)` makes a schema; `schemaBreaks(before, now)` names each published word gone (`<word> is gone`) and each break of the rest (`<word>: <break>`); `breaksSince(releases, now)` holds `now` to each release still in use (by version, oldest first) and answers those it breaks, `latest: true` to the newest only. What the releases are, parlance does not keep, and asks no file to be kept by hand: they are what was released, and come from where releases are.

- **From the release itself.** The words package at the release's tag, or its version on pub: run `schemaOf` over its generated words. A cache of it (in `.dart_tool`) is a cache, never committed.
- **From a registry of frozen versions**, where a host's platform keeps what it shipped (widlet's): it answers each released schema.
- **Against every version still in use**, not the last only (`breaksSince` does so unless told `latest`): a guest built two releases ago runs beside the newest owner. A break accepted once on purpose hides, release by release, from every later comparison, while a part built before it still runs.
- **A schema kept in the repository** (`schema/<name>.json`, a test holding the words to it) is the fallback; it is the one that goes stale, as nobody keeps a generated file up.

A break found is fixed by §25.2, or accepted on purpose: the next release is the new baseline, and parts built against the old words see a mismatch when they meet the new.

### 25.4 At run time: what each part meets

Whatever passed release, a part may still meet a word otherwise than it holds it: an owner rolled out before or after it, a host not updated. Two things tell it, with no code of the part's own beyond using its client.

- **The part's own view of it** (§6.5). A typed handle's and a client's `status` hold the word met to the word the code holds: `WordMismatch(breaks)` instead of ready. `client.mismatches` lists every word of the vocabulary that does not match, with its breaks. A status by name has no type, and never says it. Each pair of a word and a definition is judged once; a status asked again answers at once.
- **The host's view of every part** (§6.9). A client made tells the registry the code was built against its vocabulary (`view.builtAgainst(words, from:)`), and from which words package and version (`notes_words 1.2.0`, written by the generator from the package's pubspec into the vocabulary's `WordSet.from`). The registry judges each word told as it is told and whenever the word comes, goes or is defined again (an owner attached or synced, a participant joined again), and keeps the result: `registry.mismatches` (`Mismatch {by, word, breaks, from}`), `mismatchChanges`, a warning in its `catalog` log, or with no log, in development, the developer log. A word missing is no mismatch: it is absent, and its status says so.

**Told by fingerprint.** Across a connection a part tells each word's fingerprint first, as an Avro handshake tells a protocol by its hash: the SHA-256 of the schema's canonical form (`canonicalSchema`, `fingerprintOf`: every object's keys in order, descriptions left out, so a schema that crossed a wire in another order of keys is one fingerprint; and all the rule judges kept in, defaults and bounds too, unlike Avro's parsing form, which leaves defaults out). The host answers the fingerprints it does not know, and the part sends those schemas; the registry keeps the schemas told it by fingerprint (`Registry.knownSchemas`, 4096, the least recently told going first), so a hundred guests of one words version cost one schema. A new session is told again, by fingerprint.

**A possible break, met.** An enum value or a variant added to what a part reads is a break only some values meet (`certain: false`): one may never come. The registry tells it certain once one does: a state written, a fact said, or an answer to that part holding the value at the break's path, however deep (`type.item.fields.mode.type.values`). Only words some part reads otherwise are looked into, and only their values, so the rest costs nothing. A break met stays certain while the part holds those words.

Both views are **diagnostics**: nothing waits on them, nothing is refused by them, a part that tells nothing works as before. What to do with a mismatch (not to start a guest, to roll it back, to show a feature as unavailable) is the host's decision, made outside parlance; a break's `kind` and `certain` and the mismatch's `from` are what such a decision reads.

The client tells its whole vocabulary, so a word the part never uses may be told as a mismatch. That is the price of knowing as the part starts, not at its first use of the word.

### 25.5 Old callers' params

What a part told it was built against, the registry also uses for one thing more, as Avro's reader skips a field the writer wrote that it does not know: a call by a part whose words of the command are told otherwise (a `Mismatch` of it) has the params it gives and the command no longer takes left out, rather than refused. Code built before a param went goes on calling. Only the params of the call itself, not fields deeper in them; only for a part that told what it was built against (a client does, as it is made); a part that told nothing is refused as before. What it gave is not heard: the mismatch still says the param is gone (`params.fields.fade: was optional, is nothing`), and the call is logged (`calls`, `params left out`).

### 25.6 Below the words: the protocol

The protocol under the words grows as they do (§14): its major never changes, what is added comes as a named feature the host lists, and a participant uses only what the host speaks. A guest built against a newer parlance than its host joins and does without what the host lacks; only a feature it requires (`requires:`), missing, refuses it (`ProtocolMismatch`, saying which), before any word is judged. A feature's name never changes its meaning, and goes only when nothing needs it. So a module updated apart from its host needs no parlance of the host's; what it needs of the host it says.

### 25.7 Where each check runs

| What | When | Who | Against |
|---|---|---|---|
| the compiler | build | automatic | the words of the same build |
| a value's check (`TypeMismatch`) | every write, call, fact | the registry | the word's type |
| one owner per word | defining | the registry | the catalog |
| `schemaBreaks`, `breaksSince` | before release | the author, in a test or a tool | the words as released (§25.3) |
| `WordMismatch` | run time, when asked | the part | the word as defined now |
| `Mismatch` | run time, as told and as words change | the registry, for the host | every part's words as built |
| params left out | each call of a part told otherwise | the registry | the part's words as built |
| a possible break met | each write, fact and answer of a word a part reads otherwise | the registry | the values it holds |
| `ProtocolMismatch` | join, joining again | the participant | the host's major and features |

### 25.8 Not done yet

- **A tool to compare against a release** (`--against <tag | directory | registry>`): today a test calls `breaksSince` with releases it fetches itself.
- **Use beside mismatch**: a `Mismatch` does not say whether the part has used the word (§6.8 counts that); joined, a host could tell a break that bites from one that does not.

### 25.9 The same idea elsewhere

What this scheme borrows, for a reader who knows them: frozen versions that are only appended to and checked at build (Android stable AIDL, `aidl_api/<name>/<V>` with a hash; protobuf's `buf breaking --against` a git ref, with no snapshot file); a check against every version, not the last (Confluent Schema Registry's `*_TRANSITIVE`, Avro's `validateAll`); from Avro besides, the reader and the writer (its `SchemaCompatibility`: a field the reader lacks skipped, one it needs a default, integers promoted to numbers, a writer's union read branch by branch), a break as data with its place and kind (its `Incompatibility`: type, JSON pointer, both fragments), a break that waits for the value that meets it (its `Resolver`'s deferred `ErrorAction`), a reader's enum default for a symbol it does not know, a judgment kept per pair, a handshake by fingerprint over a canonical form with the schema sent only when unknown (its IPC `Requestor` and `Responder`), and the reader skipping what it does not know (§25.5); a version of the words told with them (an IPC handshake's `meta`); a warning rather than a refusal by default, strictness the host's to turn on (Module Federation's shared versions, `strictVersion`); knowing who uses what before removing it (Apollo GraphOS operation checks, Pact's broker and `can-i-deploy` over what is deployed); a removal only by a new version (Kubernetes' deprecation policy, rule 1).
