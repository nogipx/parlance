# parlance_generator

Makes a module's typed parlance words from one abstract Dart class: the enums of its states, commands, queries and facts, the records of their params, their shapes, and the list of them all. The class is the truth; the contract is `parlance/skills/parlance/references/schema.md` (SPEC §23).

```yaml
dependencies:
  parlance: any
dev_dependencies:
  build_runner: ^2.11.1
  parlance_generator: any
```

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

  @FactWord()
  void clipped({required int volume});
}
```

`fvm dart run build_runner build` writes `PlayerState.volume`, `PlayerCommand.setVolume` (params `PlayerSetVolume = ({int volume})`), `PlayerFact.clipped`, the vocabulary `playerWords`, the owner base `PlayerOwnerBase` and the client, `IPlayerClient` with `PlayerClient` over a participant, into `player.g.dart` (`@Vocabulary('player', owner: false, client: false)` leaves those out). The owner writes only its handlers; each state is an object of the base (`volume.set(50)`, `volume.value`, `volume.remove()`), which keeps what it sets and writes it once attached, and what a handler does follows from its call:

```dart
final class Deck extends PlayerOwnerBase {
  Deck() {
    volume.set(50);
  }

  @override
  void setVolume({required int volume}) {
    this.volume.set(volume);
    if (volume > 90) clipped.say(volume: volume);
  }
}
```

`main` grants the vocabulary to the module's participant and attaches the owner to it: `host.participant(Who.player, vocabularies: [playerWords]).attach({'deck': Deck()})`; its name is written only in `@Vocabulary`, and disposing the participant takes the owner with it.

Every word is named in its vocabulary, and a vocabulary is one owner's. Another module uses the words through the client, over its participant, here or across a connection: the one way a part uses words. An owner that uses them makes the client in its constructor, `PlayerClient.of(this)`, and hears it at once: `hear(PlayerClient.of(this).clippedFacts, ...)`.

```dart
final IPlayerClient player = PlayerClient(participant); // a test gives a stand-in
player.volumeChanges.listen(show);
await player.setVolume(volume: 30); // throws CallNotDone when refused
```

Made, the client tells the registry it was built against the vocabulary, and from which words package and version (the generator reads them from the package's pubspec into `playerWords.from`, `player_words 1.2.0`): the host sees in `registry.mismatches`, and in its log, where a word is defined otherwise than this code holds it (a module updated apart) and which version the part took it from, with no code of yours.

Hold the words to every release still in use, so a published word does not change by accident; the releases' schemas come from where releases are (a tag, pub, a registry of frozen versions, SPEC §25.3):

```dart
expect(breaksSince(releases, schemaOf(playerWords.words)), isEmpty);
```

`test/fixtures/player.dart` shows every kind of word, bounds, defaults and a json_serializable class; `test/generated_test.dart` holds what its words do in a registry, `test/errors_test.dart` what the generator refuses.

## Before a release: the frozen libraries

`package:parlance/schema.dart` and `app.dart` are frozen: what they show only grows, and a words package's `.g.dart` made by an earlier release builds with the library now. Before a release, in this package:

```sh
fvm dart run tool/frozen.dart              # against the last v* tag
fvm dart run tool/frozen.dart --since <ref>
```

It compares the two libraries' public surface (every name, every public member, with its signature) at the release's tag with the one now, and builds the fixtures' generated code of that tag with the library now; anything gone, changed or not building is printed, and it exits 1. Nothing is kept in the repository to compare with. The behaviour the libraries promise is held by `packages/parlance/test/contract/`, written with `app.dart` alone.
