/// What every level shares: a player's volume, as words, and a knob that
/// speaks only through the core's interfaces.
library;

import 'package:parlance/registry.dart';

/// The params of setting the volume.
typedef SetVolume = ({int volume});

/// What is said when the volume went too high.
typedef Clipped = ({int volume});

/// The loudest the player goes before it says it clipped.
const loud = 90;

/// A part of the app that turns the volume, hears when it clipped and
/// shows it. It knows the five interfaces only, so it runs on any level
/// unchanged.
final class Knob {
  Knob({
    required IStateReader<int> volume,
    required ICommandCaller<SetVolume, void> setVolume,
    required IFactListener<Clipped> clipped,
  }) : _volume = volume,
       _setVolume = setVolume {
    clipped.stream.listen((c) => print('  knob hears: clipped at ${c.volume}'));
  }

  final IStateReader<int> _volume;
  final ICommandCaller<SetVolume, void> _setVolume;

  Future<void> turnTo(int volume) async {
    await _setVolume.call((volume: volume));
    print('  knob shows: ${_volume.value}');
  }
}

// --- The words, for the levels with a registry -------------------------------

const _setVolume = RecordShape<SetVolume>(
  {'volume': Part(Plain(IntType(min: 0, max: 100)))},
  to: _setVolumeTo,
  from: _setVolumeFrom,
);
Map<String, Object?> _setVolumeTo(SetVolume p) => {'volume': p.volume};
SetVolume _setVolumeFrom(Map<String, Object?> m) =>
    (volume: m['volume']! as int);

const _clipped = RecordShape<Clipped>(
  {'volume': Part(Plain(IntType()))},
  to: _clippedTo,
  from: _clippedFrom,
);
Map<String, Object?> _clippedTo(Clipped c) => {'volume': c.volume};
Clipped _clippedFrom(Map<String, Object?> m) => (volume: m['volume']! as int);

enum PlayerState<T> implements IStateWord<T> {
  volume<int>('player.volume', Plain(IntType(min: 0, max: 100)));

  const PlayerState(this.name, this.shape);
  @override
  final String name;
  @override
  final Shape<T> shape;
  @override
  String? get key => null;
}

enum PlayerCommand<P, R> implements ICommandWord<P, R> {
  setVolume<SetVolume, void>('player.volume.set', _setVolume);

  const PlayerCommand(this.name, this.params);
  @override
  final String name;
  @override
  final RecordShape<P> params;
  @override
  Shape<R>? get returns => null;
}

enum PlayerFact<T> implements IFactWord<T> {
  clipped<Clipped>('player.clipped', _clipped);

  const PlayerFact(this.name, this.shape);
  @override
  final String name;
  @override
  final Shape<T> shape;
}

/// Who acts in the levels with a registry.
abstract final class Who {
  static const player = Principal('player');
  static const listener = Principal('listener', 'ann');
  static const guest = Principal('guest', 'bob');
  static const phone = Principal('phone', 'ann-phone');
  static const agent = Principal('agent', 'demo');

  /// Everyone but guests may turn the volume.
  static const turners = Callers({
    'listener': Access.allow,
    'phone': Access.allow,
    'agent': Access.allow,
    'link': Access.allow,
  });
}

/// Defines the player's words in [r] and serves its command: the player
/// part of the app, as the registry sees it.
void definePlayer(Registry r) {
  final volume = r.state(PlayerState.volume).define(by: Who.player);
  final clipped = r.fact(PlayerFact.clipped).define(by: Who.player);
  r.command(PlayerCommand.setVolume).define((c) {
    final cause = c.causeFor(Who.player);
    volume.set(c.params.volume, cause: cause);
    if (c.params.volume > loud) {
      clipped.emit((volume: c.params.volume), cause: cause);
    }
  }, callers: Who.turners);
  volume.set(50);
}

/// Lets ticks, links and remote work through what was just done.
Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 30));
