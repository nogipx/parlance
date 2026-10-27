# parlance contract: schema and the generator (§23)

`package:parlance/schema.dart`; the generator is the package `parlance_generator`.

## 23. A module's words, written once

### 23.1 The class is the truth

A module writes its words once, as an abstract Dart class in a library that imports `package:parlance/schema.dart` (it exports all the generated code names: registry, participant, owners, view), marked `@Vocabulary(namespace)`; `parlance_generator` (build_runner, into the library's `.g.dart` part, beside json_serializable's) makes the typed words of §18 from it. Nothing reads the class at run time, and no yaml is needed (a yaml may generate the class, never replace it).

```dart
import 'package:parlance/schema.dart';

part 'player.g.dart';

@Vocabulary('player')
abstract class Player {
  @StateWord()
  @Range(min: 0, max: 100)
  int get volume;

  @CommandWord(name: 'volume.set')
  void setVolume({@Range(min: 0, max: 100) required int volume});

  @QueryWord()
  List<Track> search({@Length(max: 40) required String text, int? limit});

  @FactWord()
  void finished(Track track);
}
```

- **Words.** A getter marked `@StateWord(name:, key:)` is a state, its type the value's (`key`: the entity kind of a keyed state). A method marked `@CommandWord` is a command: its named parameters the params, its return type the answer (`void`, `Future<void>`: none). `@QueryWord`: a query (§6.6), its return type required. `@FactWord`: a fact returning `void`, its named parameters the payload, or its one positional parameter the payload itself. An abstract member marked with none is refused, so no word is forgotten.
- **Names.** `<namespace>.<name>`; `name` by default is the member's in snake case (`setVolume`: `set_volume`); `name: ''` is the namespace itself (`signal`, beside `signal.raise`). Two members of one name are refused, as is a name that is not dotted lowercase.
- **One library, several vocabularies.** A library may say several, each class in a part of it (`_index.dart`: `part 'scenes.dart'; part 'sound.dart'; part '_index.g.dart';`): their words go into its one `.g.dart`, and what they share (a record's shape) is made once.
- **One vocabulary, one namespace.** Every name of a vocabulary is in its namespace, with no way out of it: the name tells whose word it is and which file says it, and a module cannot take words of another's namespace by its own declaration. A part with words in two namespaces is two vocabularies (and two owners), or one namespace with a nested name (`record.replay.*`); a participant may hold several (§22).
- **Types.** `bool`, `int`, `num`, `String`, a Dart enum, `List<T>`, `Map<String, T>`, `T?`, `Object?` (any value, null too), a record of named fields, and a class that serializes itself (a `fromJson` constructor and a `toJson` method: json_serializable, freezed), as `JsonShape` with its type read from its fields (§23.2). `double` is refused: JSON does not keep `1.0` apart from `1`, so a number is `num` or `int`. Anything else is refused with the types it may be.
- **Records.** A record of named fields is an object (`RecordShape`), made once per typedef and named after it (`typedef Note = ({...})`: `_$NoteShape`), its fields in the order the typedef says them. A record keeps no annotations of its own, so they are read from the typedef's fields: `@Describe`, `@FieldName`, `@Default` and the bounds, as a parameter has them. A nullable field may be left out. An unnamed record (`({String id}) put(...)`) is named after where it is.
- **Meta.** `meta:` on any word (`@StateWord(meta: {'label': 'Muted'})`): what editors show of it, its descriptor's; JSON only.
- **Constants by name.** A constant the class names (`callers: Who.crew`, `@Range(min: minDb)`, `key: inputKind`, `meta: labels`) is named in the generated code too, so it follows the constant; only a literal is copied.
- **Bounds.** `@Range(min:, max:)` on a number, `@Length(max:)` on a text (its length), a list (its items) or a map (its entries), `@Ref(kind)` on a text that names an entity (§3). On a state's getter they bound the value; on a parameter, that param.
- **Params.** Each parameter is a field of the params record. One that is not required, or has a default, may be left out (`optional`); its shape is the value's. One required and nullable must be said, null being a value of its own (`Nullable`). A default is the field's default in the schema (a bool, a number, a text, an enum value, or a list or a map of them). `@Describe('...')` says what it is, for people and agents; `@FieldName('in')` names it in JSON when its Dart name cannot be (`in` is Dart's); `@Millis(max:)` makes an `int` of milliseconds a duration. No parameters: `()` and `RecordShape.none`.
- **Facts.** `@FactWord(open: true)`: others may say it too, beside its owner (§7).

### 23.2 What it makes

- An enum per kind the class has: `<Class>State`, `<Class>Command`, `<Class>Query`, `<Class>Fact`, each value the member's name, implementing `IStateWord`, `ICommandWord`, `IQueryWord`, `IFactWord`.
- A record per params or payload, `<Class><Member>` (`PlayerSetVolume = ({int volume})`), and its `RecordShape`.
- `<class>Words`, the vocabulary (`WordSet`: its namespace and every word): what `main` grants a participant, `registry.participant(who, vocabularies: [playerWords])` (the same for one served across a connection, `.serve(endpoint)`), so the namespace is written once, in `@Vocabulary`, never again as a string; each word is checked to lie in it. Words named at run time are defined in the vocabulary's namespace (`defineMore`); a participant whose words all come at run time gets `WordSet.open(namespace)`. Also for `Owner.words` (§19.1) and `schemaOf`.
- `<Class>Owner`, the owner base (§23.4), and `<Class>Client`, the consumer's (§23.5).
- A class's JSON type: the parameters of the factory freezed redirects, or its own instance fields (json_serializable), renamed by `@JsonKey(name:)`, left out by `@JsonKey(includeToJson: false)`; a nullable field may be absent; `DateTime` is a text; what it cannot tell is any value. A class whose fields are classes must give JSON all the way down (`explicitToJson: true`), or writing it is refused (§18).

### 23.4 The owner base

Unless `@Vocabulary(owner: false)`, it also makes `<Class>Owner`, an `abstract base class` extending `Owner` (§19). An owner extends it (`final class Deck extends PlayerOwner`) and writes only its handlers and `sync()`; a handler it forgets does not compile.

- Each state has a writer by the member's name (`volume.set(50)`), and each fact a method of its own params and a `cause` (`clipped(volume: 95, cause: call.inReply)`), defined in `define(p)`, kept with the owner. A fact's param named `cause` is refused.
- Each command and query is served by an abstract method of the member's name, returning what the class declares, taking the call: `void setVolume(CommandCallOf<PlayerSetVolume> call)`, `List<Track> search(QueryAsk<PlayerSearch> ask)`. It takes the call, not bare params, for its cause: `call.inReply` is the cause of what the owner writes, says and calls in reply (`causeFor` the part that serves it), so the trail shows the call led to it; causes never go through zones.
- What the class says of a word, its define is given: `readers` (`@StateWord`, `@FactWord`), `callers`, `deadline`, `askers` (`@QueryWord`). With `available: true` it asks `String? whyNot<Member>()`, an abstract method too. Callers left unsaid are the participant's default (§22.2).
- After the words, `define` calls `defineMore(p)`, empty by default, for what the class does not say: kinds, guards, words named at run time. A member named as one of `Owner`'s own (`sync`, `keep`, `define`...) is refused.

### 23.5 The client

Unless `@Vocabulary(client: false)`, it makes `<Class>Client(view)`: the words as another module uses them, over any `IRegistryView` (§20): its participant (here or across a connection), a `LocalView`. A screen, a bloc or a repository takes it and knows no word, shape or record.

- A state: `volume` (now), `volumeChanges` (now, then whenever it changes, deduplicated; while listened to, a remote view keeps it). Keyed: `speakerLevelOf(speaker)`, `speakerLevelAll`, `speakerLevelChanges(speaker)`.
- A command or a query: a method with the class's own parameters, defaults and all (`setVolume(volume: 95)`, `skip()`, `search(text: 'A')`), answering its value; a call not done (refused, failed, no answer in time, lost) throws `CallNotDone` with its result, so `whyNot` and the refusal's code are there.
- A fact: a stream of `Fact<T>`, said from now on (`clipped`): its payload, and the message (id, cause) for what a consumer does to follow from it (`Cause(me, parent: f.message.id)`).
- `status(word)` and `statusChanges(word)` (§6.5), for a part that shows a word missing or not permitted.
- A member it would have twice (`total` and a command `totalChanges`), or named `view`, `status`, `statusChanges`, is refused.

### 23.3 The schema a module keeps

`schemaOf(words)` says each word by name: its kind and its types, as JSON. A module keeps it beside its words (a file in its repository) and a test compares the next with it: `schemaBreaks(before, now)` names each published word gone or changed (its kind, its types or its key); a word added is no break, nor a param a command or query takes now that a caller may leave out (optional, or with a default), since every call made before still passes. A break is either a new version of the word (§1), the old one kept, or a change accepted on purpose by writing `now` as the new baseline. Inside one build the compiler already tells a breaking change; the kept schema matters for what outlives a build: modules across a connection, stored calls, agents.
