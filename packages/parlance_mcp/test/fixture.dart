import 'package:parlance/tools.dart';
import 'package:parlance/src/registry/registry.dart' show RawRegistry;

const user = Principal('user', 'local');
const agent = Principal('agent', 'claude');
const visitor = Principal('visitor', 'v1');
const owner = Principal('host', 'house');

/// A small host: rooms and inputs, a focus room, a lock and keyed
/// gains, all served by handlers that write what they are asked.
base class Fixture {
  Fixture({Registry? registry}) : r = registry ?? Registry(onError: _rethrow) {
    r.registerKind(
      EntityKind('room', list: () => [for (final s in rooms) EntityRef(s)]),
    );
    r.registerKind(
      EntityKind('input', list: () => [for (final i in inputs) EntityRef(i)]),
    );
    focus = r.defineState(
      StateDescriptor('house.focus', type: const ChoiceType('room')),
      by: owner,
    );
    locked = r.defineState(
      StateDescriptor('door.locked', type: const BoolType()),
      by: owner,
    );
    chime = r.defineState(
      StateDescriptor(
        'door.chime',
        type: const NumType(min: -60, max: 12),
        key: 'input',
      ),
      by: owner,
    );
    r.defineCommand(
      CommandDescriptor(
        'house.show',
        params: const ObjectType({'room': Field(ChoiceType('room'))}),
        callers: const Callers({
          'user': Access.allow,
          'agent': Access.allow,
          'visitor': Access.warn,
          'system': Access.allow,
        }),
      ),
      (c) {
        shown.add(c.params['room'] as String);
        focus.set(c.params['room'], cause: c.causeFor(owner));
      },
    );
    r.defineCommand(
      CommandDescriptor(
        'door.lock',
        params: const ObjectType({'on': Field(BoolType())}),
        callers: Callers.only(['user', 'agent', 'system']),
      ),
      (c) {
        locks.add(c.params['on'] as bool);
        locked.set(c.params['on'], cause: c.causeFor(owner));
      },
    );
    r.defineCommand(
      CommandDescriptor(
        'door.chime.set',
        params: const ObjectType({
          'input': Field(ChoiceType('input')),
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

  final Registry r;
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
