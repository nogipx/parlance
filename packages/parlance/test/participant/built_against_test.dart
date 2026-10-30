import 'package:parlance/tools.dart';
import 'package:parlance/schema.dart' show schemaOf;
import 'package:parlance/testing.dart';
import 'package:rpc_dart/rpc_dart.dart';
import 'package:parlance/src/registry/registry.dart' show RawRegistry;
import 'package:test/test.dart';

/// What a part was built against, told to the registry (SPEC §6.9): the
/// registry says where a word is defined otherwise, as the part tells it
/// and as words come, go and are defined again, here and across a
/// connection. Diagnostics only: nothing is refused for it.
enum Built<T> implements IStateWord<T> {
  volume<int>('deck.volume', Plain(IntType(min: 0, max: 100))),
  mode<String>('deck.mode', Plain(EnumType(['a', 'b'])));

  const Built(this.name, this.shape);
  @override
  final String name;
  @override
  final Shape<T> shape;
  @override
  String? get key => null;
}

/// The volume as its owner defines it now: it may go higher than code
/// built against it reads.
enum Now<T> implements IStateWord<T> {
  volume<int>('deck.volume', Plain(IntType(min: 0, max: 150)));

  const Now(this.name, this.shape);
  @override
  final String name;
  @override
  final Shape<T> shape;
  @override
  String? get key => null;
}

typedef Turn = ({int volume, bool? fade});
typedef TurnNow = ({int volume});

/// The command as code was built against it: it may fade.
enum BuiltCommand<P, R> implements ICommandWord<P, R> {
  turn<Turn, void>('deck.turn');

  const BuiltCommand(this.name);
  @override
  final String name;
  @override
  RecordShape<P> get params => _turn as RecordShape<P>;
  @override
  Shape<R>? get returns => null;
}

final _turn = RecordShape<Turn>(
  {
    'volume': const Part(Plain(IntType())),
    'fade': const Part(Plain(BoolType()), optional: true),
  },
  to: (t) => {'volume': t.volume, 'fade': ?t.fade},
  from: (m) => (volume: m['volume']! as int, fade: m['fade'] as bool?),
);

/// The command as its owner serves it now: fading went.
enum NowCommand<P, R> implements ICommandWord<P, R> {
  turn<TurnNow, void>('deck.turn');

  const NowCommand(this.name);
  @override
  final String name;
  @override
  RecordShape<P> get params => _turnNow as RecordShape<P>;
  @override
  Shape<R>? get returns => null;
}

final _turnNow = RecordShape<TurnNow>(
  {'volume': const Part(Plain(IntType()))},
  to: (t) => {'volume': t.volume},
  from: (m) => (volume: m['volume']! as int),
);

const deck = Principal('deck');
const guest = Principal('widlet', 'b');
const higher = [
  WordBreak('type.max', BreakKind.bound, 100, 150, certain: false),
];

void main() {
  late TestHost host;
  late List<Mismatch> told;

  setUp(() {
    host = TestHost();
    told = [];
    host.registry.mismatchChanges.listen(told.add);
  });
  tearDown(() => host.dispose());

  IRawParticipant owner() =>
      host.participant(deck, vocabularies: [WordSet.open('deck')]).raw;

  for (final across in [false, true]) {
    group(across ? 'across a connection' : 'in this process', () {
      Future<IParticipant> asGuest() async {
        if (!across) return host.participant(guest);
        final p = await host.join(guest);
        await p.settle();
        return p;
      }

      Future<void> settled(IParticipant p) async {
        if (p is RemoteParticipant) await p.flush();
        await pumpEventQueue();
      }

      test('a word defined otherwise than a part was built against is told, '
          'saying where', () async {
        final b = await asGuest();
        b.raw.builtAgainst(Built.values);
        await settled(b);
        expect(host.registry.mismatches, isEmpty, reason: 'nothing there yet');
        owner().state(Now.volume).define();
        await pumpEventQueue();
        expect(host.registry.mismatches, [
          const Mismatch(guest, 'deck.volume', higher),
        ]);
        expect(told, [const Mismatch(guest, 'deck.volume', higher)]);
      });

      test('a part built against a word there already is judged as it '
          'tells it', () async {
        owner().state(Now.volume).define();
        final b = await asGuest();
        b.raw.builtAgainst(Built.values);
        await settled(b);
        expect(host.registry.mismatches, [
          const Mismatch(guest, 'deck.volume', higher),
        ]);
      });

      test('a word defined again as it was built against ends it', () async {
        final o = owner();
        final now = o.state(Now.volume).define();
        final b = await asGuest();
        b.raw.builtAgainst(Built.values);
        await settled(b);
        now.dispose();
        o.state(Built.volume).define();
        await pumpEventQueue();
        expect(host.registry.mismatches, isEmpty);
        expect(told.last, const Mismatch(guest, 'deck.volume', []));
      });

      test('told again, it is told once', () async {
        owner().state(Now.volume).define();
        final b = await asGuest();
        b.raw
          ..builtAgainst(Built.values)
          ..builtAgainst(Built.values)
          ..builtAgainst([Built.volume]);
        await settled(b);
        expect(told, [const Mismatch(guest, 'deck.volume', higher)]);
      });

      test('a part that goes takes what it was built against', () async {
        owner().state(Now.volume).define();
        final b = await asGuest();
        b.raw.builtAgainst(Built.values);
        await settled(b);
        if (b is RemoteParticipant) {
          await b.close();
        } else {
          b.dispose();
        }
        await pumpEventQueue();
        expect(host.registry.mismatches, isEmpty);
        expect(told.last, const Mismatch(guest, 'deck.volume', []));
      });

      test('a part of it is told as itself', () async {
        owner().state(Now.volume).define();
        final b = await asGuest();
        b.child('screen').raw.builtAgainst(Built.values);
        await settled(b);
        expect(host.registry.mismatches, [
          Mismatch(guest.child('screen'), 'deck.volume', higher),
        ]);
      });
    });
  }

  test('parts across connections, told by fingerprint, are judged as by '
      'their schemas, saying the package they took the words from', () async {
    owner().state(Now.volume).define();
    final seen = <Map<String, Object?>>[];
    Future<IParticipant> joined(Principal who) async {
      final p = await host.join(who);
      await p.settle();
      return p;
    }

    final a = await joined(guest);
    final b = await joined(const Principal('widlet', 'c'));
    host.registry.mismatchChanges.listen((m) => seen.add(m.toJson()));
    a.raw.builtAgainst(Built.values, from: 'deck_words 1.2.0');
    await (a as RemoteParticipant).flush();
    final print = fingerprintOf(schemaOf([Built.volume])['deck.volume']);
    expect(host.registry.knownSchema(print), isNotNull);
    b.raw.builtAgainst(Built.values, from: 'deck_words 1.2.0');
    await (b as RemoteParticipant).flush();
    await pumpEventQueue();
    expect(host.registry.mismatches, [
      const Mismatch(guest, 'deck.volume', higher, from: 'deck_words 1.2.0'),
      const Mismatch(
        Principal('widlet', 'c'),
        'deck.volume',
        higher,
        from: 'deck_words 1.2.0',
      ),
    ]);
    expect(seen.last['from'], 'deck_words 1.2.0');
  });

  for (final across in [false, true]) {
    test('${across ? 'across a connection' : 'in this process'}, a param '
        'gone is left out of the calls of code built before it went, and '
        'still told', () async {
      final heard = <int>[];
      owner()
          .command(NowCommand.turn)
          .define(
            (c) => heard.add(c.params.volume),
            callers: const Callers({'*': Access.allow}),
          );
      final b = across ? await host.join(guest) : host.participant(guest);
      if (b is RemoteParticipant) await b.settle();
      final before = await b.raw.command(BuiltCommand.turn).call((
        volume: 3,
        fade: true,
      ));
      expect(before, isA<CallRefused>(), reason: 'not told, it is refused');
      b.raw.builtAgainst(BuiltCommand.values);
      if (b is RemoteParticipant) await b.flush();
      final r = await b.raw.command(BuiltCommand.turn).call((
        volume: 5,
        fade: true,
      ));
      expect(r, isA<CallDone<void>>(), reason: '$r');
      expect(heard, [5]);
      expect(
        [for (final m in host.registry.mismatches) '${m.breaks}'],
        ['[params.fields.fade: was optional, is nothing]'],
      );
    });
  }

  test('a word gone is no mismatch: it is missing', () async {
    final now = owner().state(Now.volume).define();
    host.participant(guest).raw.builtAgainst(Built.values);
    now.dispose();
    await pumpEventQueue();
    expect(host.registry.mismatches, isEmpty);
    expect(told.last, const Mismatch(guest, 'deck.volume', []));
  });

  test('a word under an old name is held to what the old name was built '
      'against', () async {
    host.participant(guest).raw.builtAgainst([_Old.volume]);
    owner().state(Now.volume).define();
    host.registry.alias('deck.loudness', 'deck.volume');
    expect(host.registry.mismatches, [
      const Mismatch(guest, 'deck.loudness', higher),
    ]);
  });

  test('across a connection, a new session is told again', () async {
    owner().state(Now.volume).define();
    final r = host.registry;
    final sessions = <RemoteSession>[];
    final hosts = <RpcPeerEndpoint>[];
    final connection = RpcClientConnection(
      transportFactory: (_) async {
        final (c, s) = RpcChannelTransport.pair();
        final h = RpcPeerEndpoint(transport: s);
        sessions.add(r.participant(guest).serve(h));
        h.start();
        hosts.add(h);
        return c;
      },
      backoff: const RpcFixedBackoff(Duration(milliseconds: 10)),
    );
    final p = await RemoteParticipant.join(connection);
    p.builtAgainst(Built.values);
    await p.flush();
    expect(r.mismatches, hasLength(1));

    final offline = connection.state.firstWhere((s) => s is! RpcClientOnline);
    sessions.last.dispose();
    await hosts.last.close();
    await offline;
    expect(r.mismatches, isEmpty, reason: 'the session went');

    final back = DateTime.now().add(const Duration(seconds: 5));
    while (r.mismatches.isEmpty && DateTime.now().isBefore(back)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(r.mismatches, [const Mismatch(guest, 'deck.volume', higher)]);

    await p.close();
    await connection.dispose();
    for (final s in sessions) {
      s.dispose();
    }
    for (final h in hosts) {
      await h.close();
    }
  });
}

/// The volume as code built against its old name knows it.
enum _Old<T> implements IStateWord<T> {
  volume<int>('deck.loudness', Plain(IntType(min: 0, max: 100)));

  const _Old(this.name, this.shape);
  @override
  final String name;
  @override
  final Shape<T> shape;
  @override
  String? get key => null;
}
