import 'package:parlance/tools.dart';
import 'package:parlance/testing.dart';
import 'package:test/test.dart';
import 'package:parlance/src/participant/owner.dart' show Owner;

enum Outside<T> implements IStateWord<T> {
  temperature<num>('weather.outside');

  const Outside(this.name);
  @override
  final String name;
  @override
  Shape<T> get shape => const PlainShape(NumType()) as Shape<T>;
  @override
  String? get key => null;
}

typedef Power = ({bool on});

final _power = RecordShape<Power>(
  {'on': Part(PlainShape(BoolType()))},
  to: (p) => {'on': p.on},
  from: (m) => (on: m['on']! as bool),
);

enum Heater<P, R> implements ICommandWord<P, R> {
  power<Power, void>('heater.power.set');

  const Heater(this.name);
  @override
  final String name;
  @override
  RecordShape<P> get params => _power as RecordShape<P>;
  @override
  Shape<R>? get returns => null;
}

enum Adjusted<T> implements IFactWord<T> {
  adjusted<Power>('thermostat.adjusted');

  const Adjusted(this.name);
  @override
  final String name;
  @override
  Shape<T> get shape => _power as Shape<T>;
}

enum Target<T> implements IStateWord<T> {
  heating<bool>('thermostat.heating');

  const Target(this.name);
  @override
  final String name;
  @override
  Shape<T> get shape => const PlainShape(BoolType()) as Shape<T>;
  @override
  String? get key => null;
}

/// The module under test: it heats when it is cold outside, through the
/// heater's command, and says so.
final class Thermostat extends Owner {
  Thermostat() : super(vocabulary: 'thermostat');

  late final IStateWriterOf<bool> _heating;
  late final IFactEmitterOf<Power> _adjusted;

  @override
  void define(IRawParticipant p) {
    _heating = keep(p.state(Target.heating).define());
    _adjusted = keep(p.fact(Adjusted.adjusted).define());
    listen(
      on: p.state(Outside.temperature).watch(),
      onData: (t) async {
        final on = (t ?? 20) < 15;
        await p.command(Heater.power).call((on: on));
        _heating.set(on);
        _adjusted.say((on: on));
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
    final outside = host.standInState(Outside.temperature, 10);
    final heater = host.standInCommand(Heater.power);
    host.participant(
      me,
      vocabularies: [WordSet.open('thermostat')],
      owners: [Thermostat()],
    );
    await host.settle();
    outside.set(25);
    await host.settle();

    expect(heater.params, [(on: true), (on: false)]);
    expect(host.written(Target.heating), [true, false]);
    expect(host.said(Adjusted.adjusted), [(on: true), (on: false)]);
    expect(host.callsOf(Heater.power).map((c) => c.cause.by), [
      me.child('thermostat'),
      me.child('thermostat'),
    ]);
    expect(host.errors, isEmpty);
  });

  test('the same module across a connection, as a plugin or a phone', () async {
    host.standInState(Outside.temperature, 10);
    final heater = host.standInCommand(Heater.power);
    final p = await host.join(me, vocabularies: [WordSet.open('thermostat')]);
    p.attach([Thermostat()]);
    await host.settle();
    expect(heater.params, [(on: true)]);
    expect(host.written(Target.heating), [true]);
    expect(
      host.registry.usesOf('heater.power.set').single.by,
      me.child('thermostat'),
    );
  });

  test('a stand-in takes only the vocabulary of its word', () async {
    host.participant(me, vocabularies: [WordSet.open('garden')]);
    final outside = host.standInState(Outside.temperature, 10);
    outside.set(12);
    await host.settle();
    expect(host.written(Outside.temperature), [10, 12]);
  });

  test('a stand-in command answers what it is told', () async {
    host.standInCommand(
      Heater.power,
      answer: (p) => throw StateError('broken'),
    );
    final r = await host.participant(me).raw.command(Heater.power).call((
      on: true,
    ));
    expect(r, isA<CallFailed>());
  });

  test('a stand-in state is kept as an owner keeps its own', () async {
    final host = TestHost();
    const lamp = StateWordOf<bool>(
      'lamp.on',
      PlainShape(BoolType()),
      key: 'room',
    );
    final reader = host.participant(const Principal('module', 'reader'));
    final outside = host.standInState(Outside.temperature, 10);
    final lamps = host.standInKeyed(lamp, {'hall': true});
    await host.settle();
    expect(reader.raw.read('weather.outside'), 10);
    expect(reader.raw.read('lamp.on', key: 'hall'), isTrue);
    outside.set(12);
    lamps
      ..set('kitchen', false)
      ..remove('hall');
    await host.settle();
    expect(host.written(Outside.temperature), [10, 12]);
    expect(reader.raw.readAll('lamp.on'), {'kitchen': false});
    expect(
      () => host.standInKeyed(Outside.temperature, {}),
      throwsArgumentError,
    );
    await host.dispose();
  });
}
