import 'dart:async';

import 'package:parlance/participant.dart';
import 'package:parlance/remote.dart';
import 'package:parlance/registry.dart';
import 'package:parlance/view.dart';
import 'package:parlance/src/remote/client.dart';
import 'package:parlance/src/remote/mirror.dart';
import 'package:parlance/src/view/mirror_view.dart';
import 'package:rpc_dart/rpc_dart.dart';
import 'package:test/test.dart';

import '../registry/fixture.dart';
import '../remote/remote_test.dart' show Link, settle;
import 'package:parlance/src/registry/registry.dart' show RawRegistry;

enum _State<T> implements IStateWord<T> {
  muted<bool>(Plain(BoolType()));

  const _State(this.shape);

  @override
  final Shape<T> shape;

  @override
  String get name => switch (this) {
    muted => 'audio.muted',
  };

  @override
  String? get key => null;
}

/// The muted state as code built against another owner's knows it.
enum _Text<T> implements IStateWord<T> {
  muted<String>(Plain(TextType()));

  const _Text(this.shape);

  @override
  final Shape<T> shape;

  @override
  String get name => 'audio.muted';

  @override
  String? get key => null;
}

/// A word the host has none of: built against, and no mismatch.
final class _Notes implements IStateWord<String> {
  const _Notes();
  @override
  String get name => 'studio.notes';
  @override
  Shape<String> get shape => const Plain(TextType());
  @override
  String? get key => null;
}

const _otherwise = [
  Mismatch(user, 'audio.muted', [
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
      final sub = view.changes({'audio.muted'}).listen((_) => told.add(1));
      f.program.set('main');
      f.muted.set(true);
      await settle();
      expect(told, [1], reason: 'the program is not what it asked for');
      expect(view.state(_State.muted).read(), isTrue);

      final r = await view.call('studio.show', {'scene': 'break'});
      expect(r, isA<CallDone<Object?>>());
      expect(view.read('studio.program'), 'break');
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
      addTearDown(session.close);
      late.builtAgainst(const [_Notes()]);
      await settle();
      expect(f.r.mismatches, _otherwise);
    });

    test(
      'keeps what its listeners ask for, all of them, until none does',
      () async {
        f.program.set('main');
        f.muted.set(true);
        final a = view.changes({'audio.muted'}).listen((_) {});
        final b = view.changes({'studio.program'}).listen((_) {});
        await settle();
        expect(mirror.states, {'audio.muted', 'studio.program'});
        expect(
          (view.read('audio.muted'), view.read('studio.program')),
          (true, 'main'),
        );
        await a.cancel();
        await settle();
        expect(mirror.states, {'studio.program'});
        expect(view.read('audio.muted'), isNull);
        await b.cancel();
        await settle();
        expect(mirror.states, isEmpty);
      },
    );

    test('a read after a call reads what it wrote', () async {
      final sub = view.changes({'studio.program'}).listen((_) {});
      await settle();
      await view.call('studio.show', {'scene': 'break'});
      expect(view.read('studio.program'), 'break');
      await sub.cancel();
    });

    test('hears the facts its listeners ask for', () async {
      final raid = f.r.defineFact(
        FactDescriptor('x.raid', type: const IntType()),
        by: owner,
      );
      final heard = <Object?>[];
      final sub = view.facts('x.raid').listen((m) => heard.add(m.payload));
      await settle();
      raid.emit(5);
      await settle();
      expect(heard, [5]);
      expect([for (final m in await view.recent('x.raid', 10)) m.payload], [5]);
      expect(mirror.facts, {'x.raid'});
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
        available: () => f.r.read('audio.muted') == true ? 'muted' : null,
      );
      await after();
      expect(view.status('x.go'), const WordReady());
      f.muted.set(true);
      await after();
      expect(view.status('x.go'), const WordUnavailable('muted'));
      f.muted.set(true);
      f.program.set('main');
      await after();
      go.dispose();
      await after();
      expect(seen, const [
        WordMissing(),
        WordReady(),
        WordUnavailable('muted'),
        WordMissing(),
      ], reason: 'a tick that leaves the status as it was tells nothing');
      await sub.cancel();
    }

    void closed(IRegistryView view) {
      expect(view.status('host.secret'), const WordNotPermitted());
      expect(view.status('audio.mute'), const WordReady());
      expect(view.status('audio.muted'), const WordReady());
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
      final asViewer = LocalView(f.r, by: viewer);
      expect(asViewer.status('audio.mute'), const WordNotPermitted());
      expect(asViewer.status('studio.show'), const WordReady(), reason: 'warn');
    });

    test('an old name has the status of its word', () {
      f.r.alias('audio.silent', 'audio.muted');
      expect(
        LocalView(f.r, by: user).status('audio.silent'),
        const WordReady(),
      );
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
    final sub = view.changes({'audio.muted'}).listen((_) {
      if (!done.isCompleted) done.complete();
    });
    await view.call('audio.mute', {'on': true});
    await done.future;
    expect(view.state(_State.muted).read(), isTrue);
    await sub.cancel();
  });
}
