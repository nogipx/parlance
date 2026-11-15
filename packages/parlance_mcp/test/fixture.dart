import 'package:parlance/app.dart' show Host;
import 'package:parlance/tools.dart';
import 'package:parlance/src/registry/registry.dart' show RawRegistry;

const user = Principal('user', 'local');
const agent = Principal('agent', 'claude');
const visitor = Principal('visitor', 'v1');
const owner = Principal('host', 'house');

/// A small host: rooms and inputs, a focus room, a lock and keyed
/// gains, all served by handlers that write what they are asked.
base class Fixture {
  Fixture() : host = Host(onError: _rethrow) {
    focus = r.defineState(
      StateDescriptor('host/house/house.focus', type: const TextType()),
      by: owner,
    );
    locked = r.defineState(
      StateDescriptor('host/house/door.locked', type: const BoolType()),
      by: owner,
    );
    chime = r.defineState(
      StateDescriptor(
        'host/house/door.chime',
        type: const NumType(min: -60, max: 12),
        key: 'input',
      ),
      by: owner,
    );
    r.defineCommand(
      CommandDescriptor(
        'host/house/house.show',
        params: const RecordType({'room': Field(TextType())}),
        callers: const Callers({
          'user': Access.allow,
          'agent': Access.allow,
          'visitor': Access.warn,
          'system': Access.allow,
        }),
      ),
      (c) {
        final room = c.params['room'] as String;
        if (!rooms.contains(room)) throw ArgumentError('no room $room');
        shown.add(room);
        focus.set(c.params['room'], cause: c.causeFor(owner));
      },
    );
    r.defineCommand(
      CommandDescriptor(
        'host/house/door.lock',
        params: const RecordType({'on': Field(BoolType())}),
        callers: Callers.only(['user', 'agent', 'system']),
      ),
      (c) {
        locks.add(c.params['on'] as bool);
        locked.set(c.params['on'], cause: c.causeFor(owner));
      },
    );
    r.defineCommand(
      CommandDescriptor(
        'host/house/door.chime.set',
        params: const RecordType({
          'input': Field(TextType()),
          'db': Field(NumType(min: -60, max: 12), defaultValue: 0),
        }),
        callers: Callers.only(['user', 'system']),
      ),
      (c) => chime.set(
        c.params['db'],
        key: c.params['input'] as String,
        cause: c.causeFor(owner),
      ),
    );
  }

  final Host host;
  Registry get r => host.registry;
  final List<String> rooms = ['main', 'break', 'test'];
  final List<String> inputs = ['front', 'music'];
  late final RawStateWriter focus;
  late final RawStateWriter locked;
  late final RawStateWriter chime;

  /// What the handlers were asked, in order.
  final List<String> shown = [];
  final List<bool> locks = [];
}

Never _rethrow(Object e, StackTrace s) => Error.throwWithStackTrace(e, s);
