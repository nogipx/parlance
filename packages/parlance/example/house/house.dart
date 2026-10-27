/// The house itself: its devices, and the words it owns in the registry.
library;

import 'dart:async';

import 'package:parlance/schema.dart';

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

  final StreamController<void> _changed = StreamController.broadcast();

  /// Told when a device changes on its own, not through a command.
  Stream<void> get changed => _changed.stream;

  /// Someone flips a room's switch by hand.
  void flip(String room) {
    lights[room] = !lights[room]!;
    _changed.add(null);
  }
}

/// The owner of the house's words: its base, made from [House], defines
/// them, keeps their writers and says its facts; this serves the commands
/// from [devices], answers the query and writes its states.
final class Home extends HouseOwner {
  Home(this.devices);

  final Devices devices;

  /// When a device changed by hand, it is synced on its own: nobody has
  /// to call [Owners.sync].
  @override
  Stream<void> get changes => devices.changed;

  late final TrackedKind _rooms;

  /// What [House] does not say: the rooms it keeps, and a rule of its own.
  @override
  void defineMore(IParticipant p) {
    _rooms = trackKind(
      room,
      () => [for (final id in devices.lights.keys) EntityRef(id)],
    );
    // The door stays locked at night, unless a resident says so
    // (override). It judges the house's commands only.
    keep(
      p.addGuard('night-door', (call) {
        if (call.command.name != HouseCommand.lock.name) return null;
        final unlock = call.params['on'] == false;
        final night = p.state(HouseState.mode).read() == Mode.night;
        return unlock && night ? 'the door stays locked at night' : null;
      }),
    );
  }

  @override
  void setLight(CommandCallOf<HouseSetLight> call) {
    devices.lights[call.params.room] = call.params.on;
    light.set(call.params.on, key: call.params.room, cause: call.inReply);
  }

  @override
  void setHeat(CommandCallOf<HouseSetHeat> call) {
    devices.heat = call.params.target;
    heat.set(devices.heat, cause: call.inReply);
  }

  @override
  void setMode(CommandCallOf<HouseSetMode> call) {
    devices.mode = call.params.mode;
    mode.set(devices.mode, cause: call.inReply);
  }

  @override
  void lock(CommandCallOf<HouseLock> call) {
    devices.locked = call.params.on;
    locked.set(devices.locked, cause: call.inReply);
  }

  @override
  String? whyNotLock() => devices.mode == Mode.away && !devices.locked
      ? 'the door is open and nobody is home'
      : null;

  /// Which rooms are lit: it changes nothing, so anyone may ask, and ask
  /// again.
  @override
  List<String> rooms(QueryAsk<HouseRooms> ask) => [
    for (final MapEntry(:key, :value) in devices.lights.entries)
      if (value == ask.params.lit) key,
  ];

  /// Writes what the devices say now, as one tick with its group.
  @override
  void sync() {
    for (final gone in _rooms.sync()) {
      light.remove(key: gone);
    }
    for (final MapEntry(:key, :value) in devices.lights.entries) {
      light.set(value, key: key);
    }
    heat.set(devices.heat);
    mode.set(devices.mode);
    locked.set(devices.locked);
  }

  /// The doorbell: [by] rang it, and the fact says so; its base says it
  /// (`rang`), as it says what the motion sensor sees (`motion`).
  void ring(Principal by, String who) => rang(who: who, cause: Cause(by));
}
