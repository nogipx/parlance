import 'package:parlance/participant.dart';
import 'package:parlance/registry.dart';
import 'package:parlance/remote.dart';
import 'package:rpc_dart/rpc_dart.dart';
import 'package:test/test.dart';

/// A part speaks the same on a [LocalRegistry] as on a [Registry] (SPEC
/// §22.5): the same promises hold on both, seen through participants as
/// a part sees them, so moving from one to the other changes `main` only.
typedef Song = ({String title, int volume});

const _song = RecordShape<Song>(
  {
    'title': Part(Plain(TextType())),
    'volume': Part(Plain(IntType(min: 0, max: 100))),
  },
  to: _songTo,
  from: _songFrom,
  get: _songAt,
);
Map<String, Object?> _songTo(Song s) => {'title': s.title, 'volume': s.volume};
Song _songFrom(Map<String, Object?> m) =>
    (title: m['title']! as String, volume: m['volume']! as int);
Object? _songAt(Song s, int i) => i == 0 ? s.title : s.volume;

enum DeckState<T> implements IStateWord<T> {
  playing<Song>('deck.playing');

  const DeckState(this.name);
  @override
  final String name;
  @override
  Shape<T> get shape => _song as Shape<T>;
  @override
  String? get key => null;
}

enum DeckCommand<P, R> implements ICommandWord<P, R> {
  play<Song, void>('deck.play');

  const DeckCommand(this.name);
  @override
  final String name;
  @override
  RecordShape<P> get params => _song as RecordShape<P>;
  @override
  Shape<R>? get returns => null;
}

enum DeckQuery<P, R> implements IQueryWord<P, R> {
  peek<(), int>('deck.peek');

  const DeckQuery(this.name);
  @override
  final String name;
  @override
  RecordShape<P> get params => RecordShape.none as RecordShape<P>;
  @override
  Shape<R> get returns => const Plain(IntType()) as Shape<R>;
}

enum DeckFact<T> implements IFactWord<T> {
  started<Song>('deck.started');

  const DeckFact(this.name);
  @override
  final String name;
  @override
  Shape<T> get shape => _song as Shape<T>;
}

const deckWords = WordSet('deck', [
  ...DeckState.values,
  ...DeckCommand.values,
  ...DeckQuery.values,
  ...DeckFact.values,
]);

const deck = Principal('deck');
const ann = Principal('listener', 'ann');
const bob = Principal('guest', 'bob');
const listeners = Callers({'listener': Access.allow});

/// The deck, as an owner: what the part does on either level.
final class Deck extends Owner {
  bool loaded = true;

  @override
  void define(IRawParticipant p) {
    final playing = keep(p.state(DeckState.playing).define());
    final started = keep(p.fact(DeckFact.started).define());
    keep(
      p
          .command(DeckCommand.play)
          .define(
            (c) {
              playing.set(c.params);
              started.emit(c.params);
            },
            callers: listeners,
            available: () => loaded ? null : 'nothing is loaded',
          ),
    );
    keep(
      p.query(DeckQuery.peek).define((q) {
        playing.set((title: 'sneaky', volume: 1));
        return 0;
      }),
    );
  }
}

/// A registry of either level, as `main` holds it.
abstract interface class Host {
  LocalParticipant participant(
    Principal who, {
    Iterable<WordSet> vocabularies,
    WordAccess access,
  });

  Future<void> dispose();
}

final class Full implements Host {
  final Registry r = Registry();

  @override
  LocalParticipant participant(
    Principal who, {
    Iterable<WordSet> vocabularies = const [],
    WordAccess access = WordAccess.none,
  }) => r.participant(who, vocabularies: vocabularies, access: access);

  @override
  Future<void> dispose() => r.dispose();
}

final class Light implements Host {
  final LocalRegistry r = LocalRegistry();

  @override
  LocalParticipant participant(
    Principal who, {
    Iterable<WordSet> vocabularies = const [],
    WordAccess access = WordAccess.none,
  }) => r.participant(who, vocabularies: vocabularies, access: access);

  @override
  Future<void> dispose() => r.dispose();
}

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  for (final (name, make) in <(String, Host Function())>[
    ('a Registry', Full.new),
    ('a LocalRegistry', Light.new),
  ]) {
    group('on $name', () {
      late Host host;
      late LocalParticipant owner;
      late Deck d;
      late LocalParticipant listener;
      late LocalParticipant guest;

      setUp(() {
        host = make();
        d = Deck();
        owner = host.participant(deck, vocabularies: [deckWords])
          ..attach({'deck': d});
        listener = host.participant(ann);
        guest = host.participant(bob);
      });
      tearDown(() => host.dispose());

      test('a part defines only in its vocabularies, one part each', () {
        expect(
          () => listener.state(DeckState.playing).define(),
          throwsA(isA<NotPermitted>()),
        );
        expect(
          () => host.participant(bob, vocabularies: [deckWords]),
          throwsA(isA<NotPermitted>()),
        );
      });

      test(
        'what the owner writes, says and is asked is the same to all',
        () async {
          final song = (title: 'one', volume: 40);
          final heard = listener.fact(DeckFact.started).stream.first;
          final done = await listener.command(DeckCommand.play).call(song);
          expect(done.ok, isTrue);
          expect(
            identical(guest.state(DeckState.playing).read(), song),
            isTrue,
          );
          final fact = await heard;
          expect(identical(fact.payload, song), isTrue);
          expect(fact.message.cause.by, deck.child('deck'));
          expect(listener.read('deck.playing'), {'title': 'one', 'volume': 40});
        },
      );

      test(
        'a call is held to its callers, its params and its availability',
        () async {
          final asGuest = await guest.command(DeckCommand.play).call((
            title: 'x',
            volume: 1,
          ));
          expect((asGuest as CallRefused).code, Refusal.notPermitted);
          final loud = await listener.command(DeckCommand.play).call((
            title: 'x',
            volume: 101,
          ));
          expect(loud.whyNot, 'volume: above 100');
          d.loaded = false;
          d.participant.raw.availabilityChanged('deck.play');
          expect(
            listener.status('deck.play'),
            isA<WordUnavailable>().having(
              (s) => s.why,
              'why',
              'nothing is loaded',
            ),
          );
          final unloaded = await listener.command(DeckCommand.play).call((
            title: 'x',
            volume: 1,
          ));
          expect((unloaded as CallRefused).code, Refusal.unavailable);
        },
      );

      test('a guard of the owner judges its commands', () async {
        owner.addGuard('quiet', (_) => 'quiet hours');
        final r = await listener.command(DeckCommand.play).call((
          title: 'x',
          volume: 1,
        ));
        expect(
          r,
          isA<CallRefused>()
              .having((c) => c.code, 'code', Refusal.denied)
              .having((c) => c.guard, 'guard', 'deck#quiet'),
        );
      });

      test('what follows from a call is in its conversation', () async {
        final heard = listener.fact(DeckFact.started).stream.first;
        await listener.command(DeckCommand.play).call((
          title: 'two',
          volume: 2,
        ), id: 'c1');
        final cause = (await heard).message.cause;
        expect(cause.parent, 'c1');
        expect(cause.conversation, 'c1');
        expect(cause.origin, const Origin('deck.play', ann));
      });

      test('a query changes nothing', () async {
        final r = await listener.query(DeckQuery.peek).ask(());
        expect(r, isA<CallFailed>());
        expect(guest.state(DeckState.playing).read(), isNull);
      });

      test('a scope leaves nothing of itself', () async {
        owner.dispose();
        expect(listener.status('deck.playing'), isA<WordMissing>());
        expect(
          () => host.participant(bob, vocabularies: [deckWords]),
          returnsNormally,
        );
      });
    });
  }

  group('a LocalRegistry keeps nothing past what is now', () {
    test(
      'its commands are anyone\'s unless said; a Registry asks who',
      () async {
        final light = LocalRegistry();
        final full = Registry();
        void define(LocalParticipant p) =>
            p.command(DeckCommand.play).define((_) {});
        define(light.participant(deck, vocabularies: [deckWords]));
        expect(
          () => define(full.participant(deck, vocabularies: [deckWords])),
          throwsArgumentError,
        );
        final r = await light.participant(bob).command(DeckCommand.play).call((
          title: 'x',
          volume: 1,
        ));
        expect(r.ok, isTrue);
        await light.dispose();
        await full.dispose();
      },
    );

    test('no history: no recent facts, no trail to explain', () async {
      final light = LocalRegistry();
      light.participant(deck, vocabularies: [deckWords]).attach({
        'deck': Deck(),
      });
      final ann0 = light.participant(ann);
      await ann0.command(DeckCommand.play).call((title: 'x', volume: 1));
      await settle();
      expect(await ann0.fact(DeckFact.started).recent(5), isEmpty);
      final why = await ann0.explain('deck.playing');
      expect(why.value, {'title': 'x', 'volume': 1});
      expect(why.trail, isEmpty);
      await light.dispose();
    });

    test('its parts are not served across a connection', () async {
      final light = LocalRegistry();
      final (_, s) = RpcChannelTransport.memoryPair();
      final endpoint = RpcPeerEndpoint(transport: s);
      expect(
        () => light.participant(ann).serve(endpoint),
        throwsA(isA<StateError>()),
      );
      await endpoint.close();
      await light.dispose();
    });
  });
}
