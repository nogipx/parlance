import 'dart:async';

import 'package:parlance/tools.dart';
import 'package:parlance/src/remote/client.dart';
import 'package:parlance/src/remote/mirror.dart';
import 'package:parlance/src/view/mirror_view.dart';
import 'package:rpc_dart/rpc_dart.dart';
import 'package:test/test.dart';

import '../registry/fixture.dart';
import '../remote/remote_test.dart' show Link, settle;
import 'package:parlance/src/registry/registry.dart' show RawRegistry;

enum _State<T> implements IStateWord<T> {
  locked<bool>(PlainShape(BoolType()));

  const _State(this.shape);

  @override
  final Shape<T> shape;

  @override
  String get name => switch (this) {
    locked => 'door.locked',
  };

  @override
  String? get key => null;
}

/// The locked state as code built against another owner's knows it.
enum _Text<T> implements IStateWord<T> {
  locked<String>(PlainShape(TextType()));

  const _Text(this.shape);

  @override
  final Shape<T> shape;

  @override
  String get name => 'door.locked';

  @override
  String? get key => null;
}

/// A word the host has none of: built against, and no mismatch.
final class _Notes implements IStateWord<String> {
  const _Notes();
  @override
  String get name => 'house.notes';
  @override
  Shape<String> get shape => const PlainShape(TextType());
  @override
  String? get key => null;
}

const _otherwise = [
  Mismatch(user, 'door.locked', [
    WordBreak('type.type', BreakKind.type, 'text', 'bool'),
  ]),
];

void main() {
  late Fixture f;

  setUp(() => f = Fixture());
  tearDown(() => f.r.dispose());

  group('a view of a registry in this process', () {
    test('reads at once, is told of the states it asks for and no others, '
        'and calls as its principal', () async {
      final view = LocalView(f.r, by: user);
      final told = <int>[];
      final sub = view.changes({'door.locked'}).listen((_) => told.add(1));
      f.focus.set('main');
      f.locked.set(true);
      await settle();
      expect(told, [1], reason: 'the focus is not what it asked for');
      expect(view.readAs(_State.locked.name, _State.locked.shape), isTrue);

      final r = await view.call('house.show', {'room': 'break'});
      expect(r, isA<CallDone<Object?>>());
      expect(view.read('house.focus'), 'break');
      expect(f.shown, ['break']);
      await sub.cancel();
    });

    test('what its principal may not read it does not show', () {
      f.r
          .defineState(
            StateDescriptor(
              'host.secret',
              type: const TextType(),
              readers: const Callers({'host': Access.allow}),
            ),
            by: owner,
          )
          .set('s');
      final view = LocalView(f.r, by: user);
      expect(view.read('host.secret'), isNull);
      expect(view.readAll('host.secret'), isEmpty);
    });

    test('tells the registry what its code was built against (SPEC §6.9)', () {
      LocalView(f.r, by: user).builtAgainst(_Text.values);
      expect(f.r.mismatches, _otherwise);
    });
  });

  group('a view over remote', () {
    late Link link;
    late RegistryMirror mirror;
    late MirrorView view;

    setUp(() {
      link = Link.open(f.r, user, wire: false);
      mirror = RegistryMirror()..follow(link.client);
      view = MirrorView(mirror, link.client);
    });
    tearDown(() async {
      await mirror.dispose();
      await link.close();
    });

    test(
      'tells the host what its code was built against (SPEC §6.9)',
      () async {
        view.builtAgainst(_Text.values);
        await settle();
        expect(f.r.mismatches, _otherwise);
      },
    );

    test('a telling that failed is told again, all of it', () async {
      final (c, s) = RpcChannelTransport.memoryPair();
      final host = RpcPeerEndpoint(transport: s)..start();
      final own = RpcPeerEndpoint(transport: c)..start();
      addTearDown(() async {
        await own.close();
        await host.close();
      });
      final late = MirrorView(RegistryMirror(), ParlanceClient(own));
      // Nothing serves the host yet: asking what it speaks fails.
      late.builtAgainst(_Text.values);
      await settle();
      expect(f.r.mismatches, isEmpty);
      final session = f.r.participant(user).serve(host);
      addTearDown(session.dispose);
      late.builtAgainst(const [_Notes()]);
      await settle();
      expect(f.r.mismatches, _otherwise);
    });

    test(
      'keeps what its listeners ask for, all of them, until none does',
      () async {
        f.focus.set('main');
        f.locked.set(true);
        final a = view.changes({'door.locked'}).listen((_) {});
        final b = view.changes({'house.focus'}).listen((_) {});
        await settle();
        expect(mirror.states, {'door.locked', 'house.focus'});
        expect(
          (view.read('door.locked'), view.read('house.focus')),
          (true, 'main'),
        );
        await a.cancel();
        await settle();
        expect(mirror.states, {'house.focus'});
        expect(view.read('door.locked'), isNull);
        await b.cancel();
        await settle();
        expect(mirror.states, isEmpty);
      },
    );

    test('a read after a call reads what it wrote', () async {
      final sub = view.changes({'house.focus'}).listen((_) {});
      await settle();
      await view.call('house.show', {'room': 'break'});
      expect(view.read('house.focus'), 'break');
      await sub.cancel();
    });

    test('hears the facts its listeners ask for', () async {
      final party = f.r.defineFact(
        FactDescriptor('x.party', type: const IntType()),
        by: owner,
      );
      final heard = <Object?>[];
      final sub = view.facts('x.party').listen((m) => heard.add(m.payload));
      await settle();
      party.emit(5);
      await settle();
      expect(heard, [5]);
      expect(
        [for (final m in await view.recent('x.party', 10)) m.payload],
        [5],
      );
      expect(mirror.facts, {'x.party'});
      await sub.cancel();
    });
  });

  group('word statuses', () {
    // One story told to a view: a command comes, stops being able to run
    // when the state it reads changes, and goes; [after] lets a remote
    // view catch up.
    Future<void> story(
      IRegistryView view,
      Future<void> Function() after,
    ) async {
      final seen = <WordStatus>[];
      final sub = view.statusChanges('x.go').listen(seen.add);
      await after();
      expect(view.status('x.go'), const WordMissing());
      final go = f.r.defineCommand(
        CommandDescriptor('x.go', callers: Callers.only(['user'])),
        (_) {},
        available: () => f.r.read('door.locked') == true ? 'locked' : null,
      );
      await after();
      expect(view.status('x.go'), const WordReady());
      f.locked.set(true);
      await after();
      expect(view.status('x.go'), const WordUnavailable('locked'));
      f.locked.set(true);
      f.focus.set('main');
      await after();
      go.dispose();
      await after();
      expect(seen, const [
        WordMissing(),
        WordReady(),
        WordUnavailable('locked'),
        WordMissing(),
      ], reason: 'a tick that leaves the status as it was tells nothing');
      await sub.cancel();
    }

    void closed(IRegistryView view) {
      expect(view.status('host.secret'), const WordNotPermitted());
      expect(view.status('door.lock'), const WordReady());
      expect(view.status('door.locked'), const WordReady());
    }

    void defineSecret() => f.r.defineState(
      StateDescriptor(
        'host.secret',
        type: const TextType(),
        readers: const Callers({'host': Access.allow}),
      ),
      by: owner,
    );

    test('in this process: missing, ready, unavailable, gone', () async {
      await story(LocalView(f.r, by: user), settle);
    });

    test('in this process: what the principal may not read or call is '
        'not permitted', () {
      defineSecret();
      closed(LocalView(f.r, by: user));
      final asVisitor = LocalView(f.r, by: visitor);
      expect(asVisitor.status('door.lock'), const WordNotPermitted());
      expect(asVisitor.status('house.show'), const WordReady(), reason: 'warn');
    });

    test('an old name has the status of its word', () {
      f.r.alias('door.silent', 'door.locked');
      expect(LocalView(f.r, by: user).status('door.silent'), const WordReady());
    });

    group('over remote', () {
      late Link link;
      late RegistryMirror mirror;
      late MirrorView view;

      setUp(() {
        link = Link.open(f.r, user, wire: false);
        mirror = RegistryMirror()..follow(link.client);
        view = MirrorView(mirror, link.client);
      });
      tearDown(() async {
        await mirror.dispose();
        await link.close();
      });

      test('missing, ready, unavailable, gone: the feed tells it', () async {
        await settle();
        await story(view, settle);
      });

      test('what the session may not read or call is not permitted', () async {
        defineSecret();
        await settle();
        closed(view);
      });
    });
  });

  test('a typed command through a view answers as its word says', () async {
    final view = LocalView(f.r, by: user);
    final done = Completer<void>();
    final sub = view.changes({'door.locked'}).listen((_) {
      if (!done.isCompleted) done.complete();
    });
    await view.call('door.lock', {'on': true});
    await done.future;
    expect(view.readAs(_State.locked.name, _State.locked.shape), isTrue);
    await sub.cancel();
  });
}
