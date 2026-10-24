/// The house itself: its devices, and the words it owns in the registry.
library;

import 'package:switchboard/registry.dart';

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
final class House {
  House(this.registry, this.devices) {
    final r = registry;
    _handles.add(
      r.registerKind(
        EntityKind(
          room,
          list: () => [for (final id in devices.lights.keys) EntityRef(id)],
        ),
      ),
    );
    _light = _keep(r.state(HouseState.light).define(by: Who.house));
    _heat = _keep(r.state(HouseState.heat).define(by: Who.house));
    _mode = _keep(r.state(HouseState.mode).define(by: Who.house));
    _locked = _keep(r.state(HouseState.locked).define(by: Who.house));
    _rang = _keep(r.fact(HouseFact.rang).define(by: Who.house));
    _motion = _keep(r.fact(HouseFact.motion).define(by: Who.house));

    _keep(
      r
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
    _keep(
      r
          .command(HouseCommand.setHeat)
          .define(
            (c) {
              devices.heat = c.params.target;
              _heat.set(devices.heat, cause: c.causeFor(Who.house));
            },
            callers: Who.household,
            sets: Sets(HouseState.heat.name, value: 'target'),
          ),
    );
    _keep(
      r
          .command(HouseCommand.setMode)
          .define(
            (c) {
              devices.mode = c.params.mode;
              _mode.set(devices.mode, cause: c.causeFor(Who.house));
            },
            callers: Who.household,
            sets: Sets(HouseState.mode.name, value: 'mode'),
          ),
    );
    _keep(
      r
          .command(HouseCommand.lock)
          .define(
            (c) {
              devices.locked = c.params.on;
              _locked.set(devices.locked, cause: c.causeFor(Who.house));
            },
            callers: Who.household,
            sets: Sets(HouseState.locked.name, value: 'on'),
            // Why it cannot be called now, before anyone tries.
            available: () => devices.mode == Mode.away && !devices.locked
                ? 'the door is open and nobody is home'
                : null,
          ),
    );

    // A rule of the house's own: the door stays locked at night, unless a
    // resident says so (override).
    _handles.add(
      r.addGuard('night-door', (call) {
        if (call.command.name != HouseCommand.lock.name) return null;
        final unlock = call.params['on'] == false;
        final night = r.state(HouseState.mode).read() == Mode.night;
        return unlock && night ? 'the door stays locked at night' : null;
      }),
    );
    sync();
  }

  final Registry registry;
  final Devices devices;
  final List<Handle> _handles = [];
  late final StateWriterOf<bool> _light;
  late final StateWriterOf<num> _heat;
  late final StateWriterOf<Mode> _mode;
  late final StateWriterOf<bool> _locked;
  late final FactEmitterOf<Ring> _rang;
  late final FactEmitterOf<Motion> _motion;

  H _keep<H extends Handle>(H h) {
    _handles.add(h);
    return h;
  }

  /// Writes what the devices say now, as one tick.
  void sync() => registry.batch(() {
    for (final MapEntry(:key, :value) in devices.lights.entries) {
      _light.set(value, key: key);
    }
    _heat.set(devices.heat);
    _mode.set(devices.mode);
    _locked.set(devices.locked);
  });

  /// The doorbell: [by] rang it, and the fact says so.
  void ring(Principal by, String who) =>
      _rang.emit((who: who), cause: Cause(by));

  /// A sensor saw someone in [room].
  void motion(String room) => _motion.emit((room: room));

  void dispose() {
    for (final h in _handles.reversed) {
      h.dispose();
    }
  }
}
