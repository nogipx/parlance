# parlance contract: schema and the generator (§23)

`package:parlance/schema.dart`; the generator is the package `parlance_generator`.

## 23. A module's words, written once

### 23.1 The class is the truth

A module writes its words once, as an abstract Dart class in a library that imports `package:parlance/schema.dart`, marked `@Vocabulary(name)`; `parlance_generator` (build_runner, into the library's `.g.dart` part, beside json_serializable's) makes the typed words of §18 from it. Nothing reads the class at run time, and no yaml is needed (a yaml may generate the class, never replace it).

**Two libraries a developer imports, both frozen.** `schema.dart` is what words, owners and clients work with, and all the generated code names: the annotations; the words (`WordSet`, `IStateWord`...); their shapes and value types; `Principal`, `Callers`, `Access`; `IOwner`, `OwnerTools`, `Choice`, `failCall`, `Keyed`; the participant as an interface (`IParticipant`) and the generator's one door to the words through it (`GeneratedWords`); the results of calls (`CallResult` and its five, `CallNotDone`, `Refusal`) and statuses of words (`WordStatus` and its five, `WordBreak`); the two handles the generated base writes through, `IStateWriterOf<T>` and `IFactEmitterOf<T>`. `app.dart` is what an app's `main` uses besides, a host's or a guest's: `Host`, `HostBounds`, `host.participant(...)` and its `serve(endpoint)`, `IGuestSession`, `Guest.join` / `Guest.over` and `IGuest` with its errors, `ParticipantRights`, `WordAccess`, `SessionLimits`, `LogScope`. What they show is never taken away, renamed or changed in meaning: they only grow. The rest of the library, `tools.dart`, is for tools and the package's tests, and promises nothing. A published words package's `.g.dart` refers to nothing outside `schema.dart`, and to behaviour only through its interfaces, so the library behind is free to change.

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
- **Names.** `<vocabulary>.<name>`; `name` by default is the member's in snake case (`setVolume`: `set_volume`); `name: ''` is the vocabulary itself (`signal`, beside `signal.raise`). Two members of one name are refused, as is a name that is not dotted lowercase.
- **One library, several vocabularies.** A library may say several, each class in a part of it (`_index.dart`: `part 'house.dart'; part 'garden.dart'; part '_index.g.dart';`): their words go into its one `.g.dart`, and what they share (a record's shape) is made once.
- **One vocabulary, one owner.** Every word of a vocabulary is named in it, with no way out: the name tells whose word it is and which file says it, and a module cannot take words of another's vocabulary by its own declaration. A part with words under two first names is two vocabularies (and two owners), or one vocabulary with nested names (`record.replay.*`); a participant may hold several, none inside another (§22.1).
- **Types.** `bool`, `int`, `num`, `String`, a Dart enum, `List<T>`, `Map<String, T>`, `T?`, `Object?` (any value, null too), a record of named fields, and a class that serializes itself (a `fromJson` constructor and a `toJson` method: json_serializable, freezed), as `JsonShape` with its type read from its fields (§23.2). `double` is refused: JSON does not keep `1.0` apart from `1`, so a number is `num` or `int`. Anything else is refused with the types it may be.
- **Records.** A record of named fields is an object (`RecordShape`), made once per typedef and named after it (`typedef Note = ({...})`: `_$NoteShape`), its fields in the order the typedef says them. A record keeps no annotations of its own, so they are read from the typedef's fields: `@Describe`, `@FieldName`, `@Default` and the bounds, as a parameter has them. A nullable field may be left out. An unnamed record (`({String id}) put(...)`) is named after where it is.
- **Meta.** `meta:` on any word (`@StateWord(meta: {'label': 'Muted'})`): what editors show of it, its descriptor's; JSON only.
- **Constants by name.** A constant the class names (`callers: Who.crew`, `@Range(min: minDb)`, `key: inputKind`, `meta: labels`) is named in the generated code too, so it follows the constant; only a literal is copied.
- **Bounds.** `@Range(min:, max:)` on a number, `@Length(max:)` on a text (its length), a list (its items) or a map (its entries), `@ChoiceOf(kind)` on a text that names an entity (§3). On a state's getter they bound the value; on a parameter, that param. `@Fallback()` on one value of an enum a word carries makes it what a value added later reads as (§25.2): `enum Mode { on, off, @Fallback() other }`.
- **Params.** Each parameter is a field of the params record. One that is not required, or has a default, may be left out (`optional`); its shape is the value's. One required and nullable must be said, null being a value of its own (`Nullable`). A default is the field's default in the schema (a bool, a number, a text, an enum value, or a list or a map of them). `@Describe('...')` says what it is, for people and agents; `@FieldName('in')` names it in JSON when its Dart name cannot be (`in` is Dart's); `@Millis(max:)` makes an `int` of milliseconds a duration. No parameters: `()` and `RecordShape.none`.
- **Facts.** `@FactWord(open: true)`: others may say it too, beside its owner (§7).

### 23.2 What it makes

- An enum per kind the class has: `<Class>State`, `<Class>Command`, `<Class>Query`, `<Class>Fact`, each value the member's name, implementing `IStateWord`, `ICommandWord`, `IQueryWord`, `IFactWord`.
- A record per params or payload, `<Class><Member>` (`PlayerSetVolume = ({int volume})`), and its `RecordShape`, which reads its fields by place (`get`), so the registry checks and keeps a value with no map made of it (§18).
- `<class>Words`, the vocabulary (`WordSet`: its name and every word): what `main` grants a participant, `host.participant(who, vocabularies: [playerWords])` (the same for one served across a connection, `.serve(endpoint)`), so its name is written once, in `@Vocabulary`, never again as a string; each word is checked to be named in it. A tool that names words at run time defines them in the vocabulary (§19); a participant whose words all come at run time gets `WordSet.open(name)`. Also for `schemaOf`.
- `<Class>OwnerBase`, the owner base (§23.4), and `I<Class>Client` with `<Class>Client`, the consumer's (§23.5).
- `<Class>Choices`, a constant of each name of choices its words name (a keyed state's keys, `@StateWord(key: 'room')`, and what a `@ChoiceOf('room')` names): `HouseChoices.room`, for the owner that gives them, `choices(HouseChoices.room, ...)` (§19). Nothing else is said of them: a name mistyped in an annotation is choices no owner gives, and a call naming it is refused saying so. (A kind, in parlance, is a principal's alone: `user` of `user/ann`.)
- A class's JSON type: the parameters of the factory freezed redirects, or its own instance fields (json_serializable), renamed by `@JsonKey(name:)`, left out by `@JsonKey(includeToJson: false)`; a nullable field may be absent; `DateTime` is a text; what it cannot tell is any value. A class whose fields are classes must give JSON all the way down (`explicitToJson: true`), or writing it is refused (§18).

### 23.4 The owner base

Unless `@Vocabulary(owner: false)`, it also makes `<Class>OwnerBase`, an `abstract class` implementing `IOwner` (§19): its members are the class's words and handlers, `said`, and nothing of the library's, so no name of the owner's own is ever the library's. An owner extends it (`final class Deck extends PlayerOwnerBase`) and writes only its handlers; a handler it forgets does not compile. Nothing of it is parlance's but what the class itself names: no handle, no call object, no cause.

- **A state is a field it sets.** `volume = 50` writes `player.volume`, and `volume` reads what the owner set last (null before); of a state never null, `volume = null` removes it. A keyed state is a `Keyed<T>`, read and written as a map is: `speakerLevel['left'] = 0.5`, `speakerLevel.remove('left')`, `speakerLevel['left']`, `speakerLevel.all`. The owner keeps no copy of its own: the base keeps what it set.
- **Set before it is attached, written once it is.** What the owner sets in its constructor is held, and written as one tick when `main` attaches it. Across a connection the participant writes it again after a drop by itself. Only an owner whose states come from a model of its own (a device) says more: `follow(pull, on: model.changed)` in its constructor (§19).
- **A fact is a method of its own params**: `clipped(volume: 95)`; `rang(who: 'bob', by: visitor)` says it on behalf of another, as far as the participant's rights let it. A fact's param named `by` is refused.
- **A command or a query is served by an abstract method of its own params**, as the class declares it: `void setVolume({required int volume})`, `List<Track> search({required String text, int? limit})`; what it returns is the answer, what it throws fails the call. What it sets, says and calls follows from the call it serves: the participant serves it in a zone holding the call, after an `await` too.
- **Who asks, and acting apart.** In a handler `caller` is who called; `apart(() {...})` is the owner's own act, following from no call (a timer set to act later); `together(() {...})` writes as one tick outside a handler. They are `OwnerTools`' (§19), extensions: a member of the owner's own of that name is its own, and the tool is `OwnerTools(this).caller`.
- **Not attached, it is its own test double.** `Deck()..setVolume(volume: 95)` sets `volume` to 95 and keeps `said`, each fact said with its name and payload (`[('player.clipped', (volume: 95))]`), with no registry at all.
- What the class says of a word, its define is given: `readers` (`@StateWord`, `@FactWord`), `callers`, `deadline`, `askers` (`@QueryWord`). With `available: true` it asks `String? whyNot<Member>()`, an abstract method too. Callers left unsaid are the participant's default (§22.2).
- What the class does not say the owner says in its constructor, by `OwnerTools` (§19): what it gives to choose from (`choices`), what it follows (`follow`), hears (`hear`) and lets go of (`onDispose`), and what needs its participant (`whenAttached((p) {...})`: guards, words named at run time). It overrides nothing but its handlers. A member named `said` or as what every object has (`hashCode`...), or two members of the base of one name, are refused. Its private names start `_$`, so none is the owner's either.

### 23.5 The client

Unless `@Vocabulary(client: false)`, it makes `<Class>Client(participant)`: the words as another module uses them, over its participant, here or across a connection; it is the one way a part uses words. A screen, a bloc or a repository takes it and knows no word, shape or record. What uses it takes the interface beside it, `I<Class>Client`, the same members: `main` gives `<Class>Client(participant)`, and a test gives a stand-in (by hand, or a mock of it), so the part depends on the words' meaning and never on how they come.

- A state: `volume` (now), `volumeChanges` (now, then whenever it changes, deduplicated; while listened to, a remote view keeps it). Keyed: `speakerLevelOf(speaker)`, `speakerLevelAll` (a `Map<String, T>`), `speakerLevelChanges(speaker)`.
- A command or a query: a method with the class's own parameters, defaults and all (`setVolume(volume: 95)`, `skip()`, `search(text: 'A')`), answering its value; a call not done (refused, failed, no answer in time, lost) throws `CallNotDone` with its result, so `whyNot` and the refusal's code are there.
- A fact: a stream of its payloads, said from now on (`clipped`); in the client alone, `clippedFacts`, a stream of `Fact<T>`: the payload and the message (id, cause) for what an owner does to follow from it (`Cause(me, parent: f.message.id)`).
- Made, it tells the view it was built against its vocabulary (`view.builtAgainst(words, from:)`, §6.9), `from` the words package and version the generator read from the package's pubspec (`WordSet(..., from: 'player_words 1.2.0')`): the host sees where a word is defined otherwise and of which version, with no code of the part's own. So its constructor is not `const`.
- In the client alone, `status(word)` and `statusChanges(word)` (§6.5), for a part that shows a word missing, not permitted or not as it was built against (`WordMismatch`), and `mismatches`: each word of the vocabulary there but not as built against, with where, for a check at start in development.
- The interface `I<Class>Client` says Dart's types and the vocabulary's own only: no word, status, fact message or generated record's name (a payload is its record, `({int volume})`); a refusal is thrown as an `Exception` (`CallNotDone`), caught as one. So what takes it knows nothing of parlance.
- A member it would have twice (`total` and a command `totalChanges`), or named `view`, `status`, `statusChanges`, `mismatches` or a fact's name with `Facts`, is refused.

### 23.3 The schema a module keeps

What the baseline is and where it comes from, and the scheme around it: §25.

`schemaOf(words)` says each word by name: its kind and its types, as JSON. A release's schema is the baseline the next is compared with: `schemaBreaks(before, now)` names each published word gone (`<word> is gone`) and each break of the rest (`<word>: <path>: was …, is …`), by the rule of §25.1; `breaksSince(releases, now)` against every release still in use. A word added is no break, nor what code built against `before` still reads and gives as it did (a field added to what it reads, a param it may leave out). A break is either a new version of the word (§1), the old one kept, or a change accepted on purpose by writing `now` as the new baseline. Inside one build the compiler already tells a breaking change; the released schema (§25.3: from the release's tag or version, not a file kept up by hand) matters for what outlives a build: modules across a connection, stored calls, agents. The same rule holds a word met at run time to the one code was built against (`WordMismatch`, §6.5).
