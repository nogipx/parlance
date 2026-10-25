import 'package:parlance/links.dart';
import 'package:parlance/registry.dart';

import '../registry/fixture.dart';

export '../registry/fixture.dart';

/// The registry fixture with facts, a recorder command and a links engine.
base class LinksFixture extends Fixture {
  LinksFixture({super.registry, int rateLimit = 20}) {
    raid = r.defineFact(
      FactDescriptor(
        'platform.raid',
        type: const ObjectType({
          'from': Field(TextType()),
          'viewers': Field(IntType(min: 0)),
        }),
      ),
      by: const Principal('plugin', 'twitch'),
    );
    chat = r.defineFact(
      FactDescriptor(
        'platform.chat',
        type: const ObjectType({
          'user': Field(TextType()),
          'text': Field(TextType()),
          'roles': Field(ListType(TextType()), defaultValue: <String>[]),
        }),
        open: true,
      ),
      by: const Principal('plugin', 'chat'),
    );
    r.defineCommand(
      CommandDescriptor(
        'test.say',
        params: const ObjectType({'text': Field(AnyType())}),
        callers: const Callers({'*': Access.allow}),
      ),
      (c) {
        said.add(c.params['text']);
        sayers.add(c.by);
      },
    );
    links = Links(r, rateLimit: rateLimit, onError: (e, s) => errors.add(e));
  }

  late final RawFactEmitter raid;
  late final RawFactEmitter chat;
  late final Links links;

  /// A second engine a test makes itself, after disposing [links].
  Links? links2;
  final List<Object?> said = [];
  final List<Principal> sayers = [];
  final List<Object> errors = [];

  /// Applies [defs] and fails on any problem.
  void use(List<Object?> defs) {
    final problems = links.apply(defs);
    if (problems.isNotEmpty) throw StateError('$problems');
  }

  LinkState stateOf(String id) => links.statuses[id]!.state;
}
