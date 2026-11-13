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
  final _samples = StreamController<({String room, num value})>.broadcast();

  /// The sensor's history belongs to the model, not to Parlance's registry.
  late final temperatureReadings = <String, List<num>>{
    for (final room in lights.keys) room: [20],
  };

  /// A device reports a measurement, independently of the heating target.
  void measureTemperature(String room, num value) {
    temperatureReadings[room]!.add(value);
    _samples.add((room: room, value: value));
  }

  /// Each subscriber gets an initial value and follows the same sensor source.
  Stream<num> samples(String room) => Stream.multi((out) {
    final sub = _samples.stream
        .where((sample) => sample.room == room)
        .listen(
          (sample) => out.add(sample.value),
          onError: out.addError,
          onDone: out.close,
        );
    out.onCancel = sub.cancel;
    out.add(temperatureReadings[room]!.last);
  });

  /// Main closes the model after the house and its consumers have gone.
  Future<void> close() async {
    await _samples.close();
    await _changed.close();
  }

  /// Told when a device changes on its own, not through a command.
  Stream<void> get changed => _changed.stream;

  /// Someone flips a room's switch by hand.
  void flip(String room) {
    lights[room] = !lights[room]!;
    _changed.add(null);
  }
}

/// The owner of the house's words: its base, made from [House], defines
/// them, keeps what it set and says its facts; this serves the commands
/// on [devices], answers the query and sets its states. What a handler
/// sets follows from its call: no cause is written.
final class Home extends HouseOwnerBase {
  Home(this.devices) {
    // The rooms there are, for an agent or an editor to choose from; one
    // that goes, goes of the lights too.
    choices(
      name: HouseChoices.room,
      list: () => [for (final id in devices.lights.keys) Choice(id)],
    );
    // What the devices say now: the house's devices are its model, so it
    // follows them, as one tick with its group; when a device changed by
    // hand too, so nobody has to call `sync` on its participant.
    follow(pull: _pull, on: devices.changed);
    // At night only a resident unlocks the door: not a phone, not an
    // agent. The rule is the house's, and so is who passes it.
    guard(
      id: 'night-door',
      word: HouseCommand.lock,
      check: (call) =>
          !call.params.on &&
              mode.value == Mode.night &&
              call.by.kind != 'resident'
          ? 'at night only a resident unlocks the door'
          : null,
    );
  }

  final Devices devices;

  @override
  void setLight({required String room, required bool on}) {
    devices.lights[room] = on;
    light.set(room, on);
  }

  @override
  void setHeat({required num target}) {
    devices.heat = target;
    heat.set(target);
  }

  @override
  void setMode({required Mode mode}) {
    devices.mode = mode;
    this.mode.set(mode);
  }

  @override
  void lock({required bool on}) {
    devices.locked = on;
    locked.set(on);
  }

  @override
  String? whyNotLock() => devices.mode == Mode.away && !devices.locked
      ? 'the door is open and nobody is home'
      : null;

  /// Which rooms are lit: it changes nothing, so anyone may ask, and ask
  /// again.
  @override
  List<String> rooms({required bool lit}) => [
    for (final MapEntry(:key, :value) in devices.lights.entries)
      if (value == lit) key,
  ];

  @override
  Stream<num> temperatureHistory({required String room}) =>
      Stream.fromIterable(List<num>.of(devices.temperatureReadings[room]!));

  @override
  Stream<num> temperatureSamples({required String room}) =>
      devices.samples(room);

  void _pull() {
    for (final MapEntry(:key, :value) in devices.lights.entries) {
      light.set(key, value);
    }
    heat.set(devices.heat);
    mode.set(devices.mode);
    locked.set(devices.locked);
  }

  /// The doorbell: [by] rang it, and the fact says so; its base says it
  /// (`rang`), as it says what the motion sensor sees (`motion`).
  void ring(Principal by, String who) => rang.say(who: who, by: by);
}
