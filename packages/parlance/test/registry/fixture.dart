import 'package:parlance/registry.dart';
import 'package:parlance/src/registry/registry.dart' show RawRegistry;

const user = Principal('user', 'local');
const agent = Principal('agent', 'claude');
const viewer = Principal('viewer', 'v1');
const owner = Principal('host', 'studio');

/// A small host: scenes and inputs, a program scene, a mute and keyed
/// gains, all served by handlers that write what they are asked.
base class Fixture {
  Fixture({Registry? registry})
    : r = registry ?? Registry(overriders: {'user'}, onError: _rethrow) {
    r.registerKind(
      EntityKind('scene', list: () => [for (final s in scenes) EntityRef(s)]),
    );
    r.registerKind(
      EntityKind('input', list: () => [for (final i in inputs) EntityRef(i)]),
    );
    program = r.defineState(
      StateDescriptor('studio.program', type: const ChoiceType('scene')),
      by: owner,
    );
    muted = r.defineState(
      StateDescriptor('audio.muted', type: const BoolType()),
      by: owner,
    );
    gain = r.defineState(
      StateDescriptor(
        'audio.gain',
        type: const NumType(min: -60, max: 12),
        key: 'input',
      ),
      by: owner,
    );
    r.defineCommand(
      CommandDescriptor(
        'studio.show',
        params: const ObjectType({'scene': Field(ChoiceType('scene'))}),
        callers: const Callers({
          'user': Access.allow,
          'agent': Access.allow,
          'viewer': Access.warn,
          'system': Access.allow,
        }),
      ),
      (c) {
        shown.add(c.params['scene'] as String);
        program.set(c.params['scene'], cause: c.causeFor(owner));
      },
    );
    r.defineCommand(
      CommandDescriptor(
        'audio.mute',
        params: const ObjectType({'on': Field(BoolType())}),
        callers: Callers.only(['user', 'agent', 'system']),
      ),
      (c) {
        mutes.add(c.params['on'] as bool);
        muted.set(c.params['on'], cause: c.causeFor(owner));
      },
    );
    r.defineCommand(
      CommandDescriptor(
        'audio.gain.set',
        params: const ObjectType({
          'input': Field(ChoiceType('input')),
          'db': Field(NumType(min: -60, max: 12), defaultValue: 0),
        }),
        callers: Callers.only(['user', 'system']),
      ),
      (c) => gain.set(
        c.params['db'],
        key: c.params['input'] as String,
        cause: c.causeFor(owner),
      ),
    );
  }

  final Registry r;
  final List<String> scenes = ['main', 'break', 'test'];
  final List<String> inputs = ['mic', 'music'];
  late final RawStateWriter program;
  late final RawStateWriter muted;
  late final RawStateWriter gain;

  /// What the handlers were asked, in order.
  final List<String> shown = [];
  final List<bool> mutes = [];
}

Never _rethrow(Object e, StackTrace s) => Error.throwWithStackTrace(e, s);
