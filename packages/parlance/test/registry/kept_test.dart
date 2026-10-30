import 'package:parlance/tools.dart';
import 'package:test/test.dart';

/// A word a typed owner defines in this process is kept as its Dart value
/// (SPEC §18): what is written, said, sent and answered is the value
/// itself to whoever has the word's shape, and JSON to whoever asks by
/// name.
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
  play<Song, Song>('deck.play');

  const DeckCommand(this.name);
  @override
  final String name;
  @override
  RecordShape<P> get params => _song as RecordShape<P>;
  @override
  Shape<R>? get returns => _song as Shape<R>;
}

enum DeckFact<T> implements IFactWord<T> {
  started<Song>('deck.started');

  const DeckFact(this.name);
  @override
  final String name;
  @override
  Shape<T> get shape => _song as Shape<T>;
}

const deck = Principal('deck');
const ann = Principal('listener', 'ann');

void main() {
  late Registry r;
  late LocalParticipant owner;
  late LocalParticipant listener;
  final sent = <Song>[];

  setUp(() {
    r = Registry();
    owner = r.participant(deck, vocabularies: [WordSet.open('deck')]);
    listener = r.participant(ann);
    final playing = owner.state(DeckState.playing).define();
    final started = owner.fact(DeckFact.started).define();
    owner.command(DeckCommand.play).define((c) {
      sent.add(c.params);
      playing.set(c.params);
      started.emit(c.params);
      return c.params;
    }, callers: Callers.anyone);
  });
  tearDown(() async {
    sent.clear();
    await r.dispose();
  });

  test('a call in this process sends and answers the value itself', () async {
    final song = (title: 'one', volume: 40);
    final heard = listener.fact(DeckFact.started).facts.first;
    final done = await listener.command(DeckCommand.play).call(song);
    expect(identical(sent.single, song), isTrue, reason: 'no JSON between');
    expect(identical((done as CallDone<Song>).value, song), isTrue);
    expect(
      identical(listener.state(DeckState.playing).read(), song),
      isTrue,
      reason: 'the state read is the value written',
    );
    expect(identical((await heard).payload, song), isTrue);
  });

  test('by name it is JSON, as before', () async {
    final done = await listener.call('deck.play', {
      'title': 'two',
      'volume': 50,
    });
    expect((done as CallDone).value, {'title': 'two', 'volume': 50});
    expect(sent.single, (title: 'two', volume: 50));
    expect(listener.read('deck.playing'), {'title': 'two', 'volume': 50});
    final refused = await listener.call('deck.play', {
      'title': 'x',
      'volume': 500,
    });
    expect(refused.why, 'volume: above 100');
  });

  test('what is told and recorded of it is JSON, made when asked', () async {
    final ticks = <Tick>[];
    final calls = <CallRecord>[];
    final sub = r.ticks.listen(ticks.add);
    final rec = r.calls.listen(calls.add);
    await listener.command(DeckCommand.play).call((title: 'three', volume: 1));
    await Future<void>.delayed(Duration.zero);
    final changes = [for (final t in ticks) ...t.changes];
    final facts = [for (final t in ticks) ...t.facts];
    expect(changes.single.value, {'title': 'three', 'volume': 1});
    expect(facts.single.payload, {'title': 'three', 'volume': 1});
    expect(calls.single.params, {'title': 'three', 'volume': 1});
    expect(calls.single.result.toJson(), {
      'done': true,
      'value': {'title': 'three', 'volume': 1},
    });
    await sub.cancel();
    await rec.cancel();
  });

  test('a typed value is refused as its JSON would be', () async {
    final refused = await listener.command(DeckCommand.play).call((
      title: 'loud',
      volume: 101,
    ));
    expect(refused.why, 'volume: above 100');
    expect(sent, isEmpty);
  });
}
