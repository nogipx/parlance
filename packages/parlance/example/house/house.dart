/// The house itself: its devices, and the words it owns in the registry.
library;

import 'package:parlance/owners.dart';
import 'package:parlance/participant.dart';
import 'package:parlance/registry.dart';

import 'words.dart';

/// The devices, as simple as they come: what a real host would drive.
final class Devices {
  final Map<String, bool> lights = {
    'kitchen': false,
    'hall': false,
    'living': false,
    'porch': false,
  };
  num heat = 20;
  Mode mode = Mode.home;
  bool locked = true;
}

/// The owner of the house's words: it defines them, serves its commands
/// from [devices], writes its states and emits what its sensors see.
final class House extends Owner {
  House(this.devices);

  final Devices devices;

  /// What it owns, told in `describe` as the part's: each must lie in the
  /// namespaces main gave the house.
  @override
  Iterable<IWord> get words => [
    ...HouseState.values,
    ...HouseCommand.values,
    ...HouseQuery.values,
    ...HouseFact.values,
  ];

  late final TrackedKind _rooms;
  late final StateWriterOf<bool> _light;
  late final StateWriterOf<num> _heat;
  late final StateWriterOf<Mode> _mode;
  late final StateWriterOf<bool> _locked;
  late final FactEmitterOf<Ring> _rang;
  late final FactEmitterOf<Motion> _motion;

  @override
  void define(IParticipant p) {
    _rooms = trackKind(
      room,
      () => [for (final id in devices.lights.keys) EntityRef(id)],
    );
    _light = keep(p.state(HouseState.light).define());
    _heat = keep(p.state(HouseState.heat).define());
    _mode = keep(p.state(HouseState.mode).define());
    _locked = keep(p.state(HouseState.locked).define());
    _rang = keep(p.fact(HouseFact.rang).define());
    _motion = keep(p.fact(HouseFact.motion).define());

    keep(
      p
          .command(HouseCommand.setLight)
          .define(
            (c) {
              devices.lights[c.params.room] = c.params.on;
              _light.set(
                c.params.on,
                key: c.params.room,
                cause: c.causeFor(Who.house),
              );
            },
            callers: Who.anyone,
            sets: Sets(HouseState.light.name, key: 'room', value: 'on'),
          ),
    );
    keep(
      p.command(HouseCommand.setHeat).define((c) {
        devices.heat = c.params.target;
        _heat.set(devices.heat, cause: c.causeFor(Who.house));
      }, sets: Sets(HouseState.heat.name, value: 'target')),
    );
    keep(
      p.command(HouseCommand.setMode).define((c) {
        devices.mode = c.params.mode;
        _mode.set(devices.mode, cause: c.causeFor(Who.house));
      }, sets: Sets(HouseState.mode.name, value: 'mode')),
    );
    keep(
      p
          .command(HouseCommand.lock)
          .define(
            (c) {
              devices.locked = c.params.on;
              _locked.set(devices.locked, cause: c.causeFor(Who.house));
            },
            sets: Sets(HouseState.locked.name, value: 'on'),
            // Why it cannot be called now, before anyone tries.
            available: () => devices.mode == Mode.away && !devices.locked
                ? 'the door is open and nobody is home'
                : null,
          ),
    );

    // A question it answers: which rooms are lit. It changes nothing, so
    // anyone may ask, and ask again.
    keep(
      p
          .query(HouseQuery.rooms)
          .define(
            (q) => [
              for (final MapEntry(:key, :value) in devices.lights.entries)
                if (value == q.params.lit) key,
            ],
          ),
    );

    // A rule of the house's own: the door stays locked at night, unless a
    // resident says so (override). It judges the house's commands only.
    keep(
      p.addGuard('night-door', (call) {
        if (call.command.name != HouseCommand.lock.name) return null;
        final unlock = call.params['on'] == false;
        final night = p.state(HouseState.mode).read() == Mode.night;
        return unlock && night ? 'the door stays locked at night' : null;
      }),
    );
  }

  /// Writes what the devices say now; [Owners.sync] makes it one tick.
  @override
  void sync() {
    for (final gone in _rooms.sync()) {
      _light.remove(key: gone);
    }
    for (final MapEntry(:key, :value) in devices.lights.entries) {
      _light.set(value, key: key);
    }
    _heat.set(devices.heat);
    _mode.set(devices.mode);
    _locked.set(devices.locked);
  }

  /// The doorbell: [by] rang it, and the fact says so.
  void ring(Principal by, String who) =>
      _rang.emit((who: who), cause: Cause(by));

  /// A sensor saw someone in [room].
  void motion(String room) => _motion.emit((room: room));
}
