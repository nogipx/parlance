import 'package:parlance/schema.dart';
import 'package:parlance/tools.dart';
import 'package:parlance/testing.dart';
import 'package:test/test.dart';

part 'testing_test.g.dart';

@Vocabulary('weather')
abstract class Weather {
  @StateWord('outside')
  num get outside;
}

@Vocabulary('heater')
abstract class Heater {
  @CommandWord('set_power')
  void setPower({required bool on});
}

@Vocabulary('thermostat')
abstract class Thermostat {
  @StateWord('heating')
  bool get heating;

  @FactWord('adjusted')
  void adjusted({required bool on});
}

@Vocabulary('lamp')
abstract class Lamp {
  @StateWord('on', keyOf: 'room')
  bool get on;
}

/// The module under test: it heats when it is cold outside, through the
/// heater's command, and says so.
final class _Thermostat extends ThermostatOwnerBase {
  _Thermostat() {
    final heater = IHeaterClient.of(
      owner: this,
      target: const Principal('heater'),
    );
    listen(
      on: IWeatherClient.of(
        owner: this,
        target: const Principal('weather'),
      ).outside.changes,
      onData: (t) async {
        final on = (t ?? 20) < 15;
        await heater.setPower(on: on);
        heating.set(on);
        adjusted.say(on: on);
      },
    );
  }
}

const me = Principal('module', 'thermostat');

void main() {
  late TestHost host;
  setUp(() => host = TestHost());
  tearDown(() => host.dispose());

  test('stand-ins answer for the modules a test leaves out; what the module '
      'did is read back', () async {
    final outside = host.standInState(
      WeatherState.outside,
      10,
      target: const Principal('weather'),
    );
    final heater = host.standInCommand(
      HeaterCommand.setPower,
      target: const Principal('heater'),
    );
    host.participant(me, owners: [_Thermostat()]);
    await host.settle();
    outside.set(25);
    await host.settle();

    expect(heater.params, [(on: true), (on: false)]);
    expect(host.written(ThermostatState.heating, target: me), [true, false]);
    expect(host.said(ThermostatFact.adjusted, target: me), [
      (on: true),
      (on: false),
    ]);
    expect(
      host
          .callsOf(HeaterCommand.setPower, target: const Principal('heater'))
          .map((c) => c.cause.by),
      [me.ofOwner('thermostat'), me.ofOwner('thermostat')],
    );
    expect(host.errors, isEmpty);
  });

  test('the same module across a connection, as a plugin or a phone', () async {
    host.standInState(
      WeatherState.outside,
      10,
      target: const Principal('weather'),
    );
    final heater = host.standInCommand(
      HeaterCommand.setPower,
      target: const Principal('heater'),
    );
    final p = await host.join(me, vocabularies: [WordSet.open('thermostat')]);
    p.attach([_Thermostat()]);
    await host.settle();
    expect(heater.params, [(on: true)]);
    expect(host.written(ThermostatState.heating, target: me), [true]);
    expect(
      host.registry.usesOf('heater/heater.set_power').single.by,
      me.ofOwner('thermostat'),
    );
  });

  test('a stand-in takes only the vocabulary of its word', () async {
    host.participant(me, vocabularies: [WordSet.open('garden')]);
    final outside = host.standInState(
      WeatherState.outside,
      10,
      target: const Principal('weather'),
    );
    outside.set(12);
    await host.settle();
    expect(
      host.written(WeatherState.outside, target: const Principal('weather')),
      [10, 12],
    );
  });

  test('a stand-in command answers what it is told', () async {
    host.standInCommand(
      HeaterCommand.setPower,
      answer: (p) => throw StateError('broken'),
      target: const Principal('heater'),
    );
    await expectLater(
      IHeaterClient(
        participant: host.participant(me),
        target: const Principal('heater'),
      ).setPower(on: true),
      throwsA(
        isA<CallNotDone>().having((e) => e.result, 'result', isA<CallFailed>()),
      ),
    );
  });

  test('a stand-in state is kept as an owner keeps its own', () async {
    final host = TestHost();
    final reader = host.participant(const Principal('module', 'reader'));
    final outside = host.standInState(
      WeatherState.outside,
      10,
      target: const Principal('weather'),
    );
    final lamps = host.standInKeyed(LampState.on, {
      'hall': true,
    }, target: const Principal('lamp'));
    await host.settle();
    expect(reader.raw.read('weather/weather.outside'), 10);
    expect(reader.raw.read('lamp/lamp.on', key: 'hall'), isTrue);
    outside.set(12);
    lamps
      ..set('kitchen', false)
      ..remove('hall');
    await host.settle();
    expect(
      host.written(WeatherState.outside, target: const Principal('weather')),
      [10, 12],
    );
    expect(reader.raw.readAll('lamp/lamp.on'), {'kitchen': false});
    expect(
      () => host.standInKeyed(
        WeatherState.outside,
        {},
        target: const Principal('weather'),
      ),
      throwsArgumentError,
    );
    await host.dispose();
  });
}
