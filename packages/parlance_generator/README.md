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

`fvm dart run build_runner build` writes `PlayerState.volume`, `PlayerCommand.setVolume` (params `PlayerSetVolume = ({int volume})`), `PlayerFact.clipped`, the vocabulary `playerWords`, the owner base `PlayerOwner` and the client `PlayerClient` into `player.g.dart` (`@Vocabulary('player', owner: false, client: false)` leaves those out). The owner writes only its handlers and what it has now:

```dart
final class Deck extends PlayerOwner {
  int level = 50;

  @override
  void sync() => volume.set(level);

  @override
  void setVolume(CommandCallOf<PlayerSetVolume> call) {
    level = call.params.volume;
    volume.set(level, cause: call.inReply);
    if (level > 90) clipped(volume: level, cause: call.inReply);
  }
}
```

`main` grants the vocabulary to the module's participant and attaches the owner: `Owners(r.participant(Who.player, vocabularies: [playerWords]), {'deck': Deck()})`; the namespace is written only in `@Vocabulary`.

One vocabulary is one namespace: every word's name is in it. Another module uses the words through the client, over any view: its participant, a `LocalView`, or a `MirrorView` across a connection:

```dart
final player = PlayerClient(participant);
player.volumeChanges.listen(show);
await player.setVolume(volume: 30); // throws CallNotDone when refused
```

Keep the schema in the repository and hold it in a test, so a published word does not change by accident:

```dart
final before = jsonDecode(File('schema/player.json').readAsStringSync());
expect(schemaBreaks(before, schemaOf(playerWords.words)), isEmpty);
```

`test/fixtures/player.dart` shows every kind of word, bounds, defaults and a json_serializable class; `test/generated_test.dart` holds what its words do in a registry, `test/errors_test.dart` what the generator refuses.
