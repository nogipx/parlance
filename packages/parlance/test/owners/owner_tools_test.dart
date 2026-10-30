import 'dart:async';

import 'package:parlance/app.dart';
import 'package:parlance/tools.dart' show OwnerParticipant, RawAccess;
import 'package:test/test.dart';

/// An owner has no members of the library's (SPEC §23.4): what it does
/// with it, it does by `OwnerTools`, so a name of its own stays its own.
/// And it overrides nothing: what it follows, hears, keeps and lets go of
/// it says in its constructor.
enum _State<T> implements IStateWord<T> {
  level<int>('lamp.level', PlainShape(IntType()));

  const _State(this.name, this.shape);
  @override
  final String name;
  @override
  final Shape<T> shape;
  @override
  String? get key => null;
}

/// What a lamp's device says, changed by hand too.
final class _Device {
  int level = 0;
  final StreamController<void> _changed = StreamController.broadcast();
  Stream<void> get changed => _changed.stream;
  void turn(int to) {
    level = to;
    _changed.add(null);
  }
}

final class _Lamp implements IOwner {
  _Lamp(this.device) {
    IOwner.made(
      this,
      define: (p) => _level = GeneratedWords(p).state(_State.level).define(),
    );
    follow(
      pull: () {
        pulls++;
        _level.set(device.level);
      },
      on: device.changed,
    );
    listen(on: heard.stream, onData: (_) => listened++);
    whenAttached((_) => order.add('attached'));
    onDispose(() => order.add('gone'));
    choices(name: 'bulb', list: () => [for (final b in bulbs) Choice(b)]);
  }

  final _Device device;
  late IStateWriterOf<int> _level;
  final List<String> bulbs = ['a'];
  final StreamController<int> heard = StreamController();
  final List<String> order = [];
  var pulls = 0;
  var listened = 0;

  // Its own name, as a tool of the library's is named: it stays its own.
  String get caller => 'its own caller';
}

void main() {
  late Host r;
  late IParticipant p;
  late _Device device;
  late _Lamp lamp;
  setUp(() {
    r = Host();
    device = _Device();
    lamp = _Lamp(device);
  });
  tearDown(() => r.dispose());

  /// The lamp's participant, the lamp attached.
  void attach() => p = r.participant(
    const Principal('lamp'),
    owners: [lamp],
    vocabularies: [WordSet.open('lamp')],
  );

  test('nothing runs before it is attached; what waits runs once it is, '
      'after its words', () async {
    lamp.heard.add(1);
    await pumpEventQueue();
    expect(lamp.pulls, 0);
    expect(lamp.listened, 0, reason: 'it listens once attached');
    expect(lamp.order, isEmpty);

    device.level = 3;
    attach();
    await pumpEventQueue();
    expect(lamp.order, ['attached']);
    expect(lamp.pulls, 1);
    expect(lamp.listened, 1);
    expect(GeneratedWords(p).state(_State.level).read(), 3);
    expect(r.registry.hasKind('bulb'), isTrue);
  });

  test('it follows its model: on sync, and when the model tells it, once '
      'for all told in a turn', () async {
    attach();
    p.raw.sync();
    expect(lamp.pulls, 2);

    device
      ..turn(5)
      ..turn(6);
    await p.settle();
    expect(lamp.pulls, 3);
    expect(GeneratedWords(p).state(_State.level).read(), 6);
  });

  test('a follow said once attached runs at once', () async {
    attach();
    var late_ = 0;
    lamp.follow(pull: () => late_++);
    expect(late_, 1);
    p.raw.sync();
    expect(late_, 2);
  });

  test('what it lets go of goes with it', () async {
    attach();
    await r.dispose();
    expect(lamp.order, ['attached', 'gone']);
  });

  test('a name of its own is its own: the tool is reached by the '
      'extension', () async {
    attach();
    expect(lamp.caller, 'its own caller');
    expect(OwnerTools(lamp).by, isNull);
  });
}
