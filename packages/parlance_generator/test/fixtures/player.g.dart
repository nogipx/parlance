// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'player.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Track _$TrackFromJson(Map<String, dynamic> json) => Track(
  title: json['title'] as String,
  seconds: (json['length'] as num?)?.toInt(),
  artist: json['artist'] == null
      ? null
      : Artist.fromJson(json['artist'] as Map<String, dynamic>),
);

Map<String, dynamic> _$TrackToJson(Track instance) => <String, dynamic>{
  'title': instance.title,
  'length': instance.seconds,
  'artist': instance.artist?.toJson(),
};

Artist _$ArtistFromJson(Map<String, dynamic> json) =>
    Artist(json['name'] as String);

Map<String, dynamic> _$ArtistToJson(Artist instance) => <String, dynamic>{
  'name': instance.name,
};

// **************************************************************************
// VocabularyGenerator
// **************************************************************************

/// The states of [Player].
enum PlayerState<T> implements IStateWord<T> {
  volume<int>('player.volume', Plain(IntType(min: 0, max: 100))),
  repeat<Repeat>(
    'player.repeat',
    EnumShape(Repeat.values, unknown: Repeat.off),
  ),
  playing<Track?>(
    'player.playing',
    Nullable<Track>(
      JsonShape<Track>(
        Track.fromJson,
        _$PlayerTrackToJson,
        type: ObjectType({
          'title': Field(TextType()),
          'length': Field(NullableType(IntType()), optional: true),
          'artist': Field(
            NullableType(ObjectType({'name': Field(TextType())})),
            optional: true,
          ),
        }),
      ),
    ),
  ),
  speakerLevel<num>(
    'player.speaker_level',
    Plain(NumType(min: 0, max: 1)),
    key: 'speaker',
  );

  const PlayerState(this.name, this.shape, {this.key});
  @override
  final String name;
  @override
  final Shape<T> shape;
  @override
  final String? key;
}

/// The commands of [Player].
enum PlayerCommand<P, R> implements ICommandWord<P, R> {
  setVolume<PlayerSetVolume, void>(
    'player.volume_set',
    RecordShape<PlayerSetVolume>(
      {'volume': Part(Plain(IntType(min: 0, max: 100)))},
      to: _$PlayerSetVolumeTo,
      from: _$PlayerSetVolumeFrom,
      get: _$PlayerSetVolumeAt,
    ),
    null,
  ),
  play<PlayerPlay, void>(
    'player.play',
    RecordShape<PlayerPlay>(
      {
        'track': Part(
          JsonShape<Track>(
            Track.fromJson,
            _$PlayerTrackToJson,
            type: ObjectType({
              'title': Field(TextType()),
              'length': Field(NullableType(IntType()), optional: true),
              'artist': Field(
                NullableType(ObjectType({'name': Field(TextType())})),
                optional: true,
              ),
            }),
          ),
        ),
        'repeat': Part(
          EnumShape(Repeat.values, unknown: Repeat.off),
          defaultValue: 'off',
        ),
        'on': Part(Plain(ChoiceType('speaker')), optional: true),
      },
      to: _$PlayerPlayTo,
      from: _$PlayerPlayFrom,
      get: _$PlayerPlayAt,
    ),
    null,
  ),
  skip<PlayerSkip, int>(
    'player.skip',
    RecordShape<PlayerSkip>(
      {'count': Part(Plain(IntType()), defaultValue: 1)},
      to: _$PlayerSkipTo,
      from: _$PlayerSkipFrom,
      get: _$PlayerSkipAt,
    ),
    Plain(IntType()),
  ),
  stop<(), void>('player.stop', RecordShape.none, null);

  const PlayerCommand(this.name, this.params, this.returns);
  @override
  final String name;
  @override
  final RecordShape<P> params;
  @override
  final Shape<R>? returns;
}

/// The queries of [Player].
enum PlayerQuery<P, R> implements IQueryWord<P, R> {
  search<PlayerSearch, List<Track>>(
    'player.search',
    RecordShape<PlayerSearch>(
      {
        'text': Part(Plain(TextType(maxLength: 40))),
        'limit': Part(Plain(IntType()), optional: true),
      },
      to: _$PlayerSearchTo,
      from: _$PlayerSearchFrom,
      get: _$PlayerSearchAt,
    ),
    ListShape(
      JsonShape<Track>(
        Track.fromJson,
        _$PlayerTrackToJson,
        type: ObjectType({
          'title': Field(TextType()),
          'length': Field(NullableType(IntType()), optional: true),
          'artist': Field(
            NullableType(ObjectType({'name': Field(TextType())})),
            optional: true,
          ),
        }),
      ),
    ),
  );

  const PlayerQuery(this.name, this.params, this.returns);
  @override
  final String name;
  @override
  final RecordShape<P> params;
  @override
  final Shape<R> returns;
}

/// The facts of [Player].
enum PlayerFact<T> implements IFactWord<T> {
  clipped<PlayerClipped>(
    'player.clipped',
    RecordShape<PlayerClipped>(
      {'volume': Part(Plain(IntType()))},
      to: _$PlayerClippedTo,
      from: _$PlayerClippedFrom,
      get: _$PlayerClippedAt,
    ),
  ),
  finished<Track>(
    'player.finished',
    JsonShape<Track>(
      Track.fromJson,
      _$PlayerTrackToJson,
      type: ObjectType({
        'title': Field(TextType()),
        'length': Field(NullableType(IntType()), optional: true),
        'artist': Field(
          NullableType(ObjectType({'name': Field(TextType())})),
          optional: true,
        ),
      }),
    ),
  );

  const PlayerFact(this.name, this.shape);
  @override
  final String name;
  @override
  final Shape<T> shape;
}

/// The kinds of choices [Player] speaks of: what an owner gives by
/// `choices(PlayerChoices.speaker, ...)`.
abstract final class PlayerChoices {
  static const String speaker = 'speaker';
}

/// The owner base of [Player]: it defines every word, keeps what
/// the owner set of each state and writes it, says each fact
/// by a method of its params, and serves each command and
/// query by a handler of its params. What a handler writes,
/// says and calls follows from the call it serves.
abstract class PlayerOwnerBase implements IOwner {
  PlayerOwnerBase() {
    IOwner.made(this, define: _$define, write: _$write, words: playerWords);
  }

  /// player.volume: what this owner set last, read by `value`,
  /// written by `set` and `remove`.
  final Single<int> volume = Single<int>();

  /// player.repeat: what this owner set last, read by `value`,
  /// written by `set` and `remove`.
  final Single<Repeat> repeat = Single<Repeat>();

  /// player.playing: what this owner set last, read by `value`,
  /// written by `set` and `remove`.
  final Single<Track?> playing = Single<Track?>();

  /// player.speaker_level, by speaker: what this owner set of each,
  /// read by `of`, written by `set` and `remove`.
  final Keyed<num> speakerLevel = Keyed<num>();

  IFactEmitterOf<PlayerClipped>? _$clipped;
  IFactEmitterOf<Track>? _$finished;

  /// What it said while not attached, for a test to read:
  /// each fact's name and payload, in order.
  final List<(String, Object?)> said = [];

  void _$say<T>(String fact, IFactEmitterOf<T>? e, T payload, Principal? by) {
    if (e == null) {
      said.add((fact, payload));
    } else if (by == null) {
      e.emit(payload);
    } else {
      e.emitFor(payload, by);
    }
  }

  void _$define(IParticipant participant) {
    final p = GeneratedWords(participant);
    Single.attach(
      volume,
      p
          .state(PlayerState.volume)
          .define(
            meta: const {
              'label': 'Volume',
              'steps': [0, 50, 100],
            },
          ),
    );
    Single.attach(repeat, p.state(PlayerState.repeat).define());
    Single.attach(playing, p.state(PlayerState.playing).define());
    Keyed.attach(speakerLevel, p.state(PlayerState.speakerLevel).define());
    _$clipped = p.fact(PlayerFact.clipped).define();
    _$finished = p.fact(PlayerFact.finished).define();
    p
        .command(PlayerCommand.setVolume)
        .serve((x) => setVolume(volume: x.volume));
    p
        .command(PlayerCommand.play)
        .serve(
          (x) => play(track: x.track, repeat: x.repeat, on: x.on),
          deadline: const Duration(microseconds: 5000000),
          whyNot: whyNotPlay,
        );
    p.command(PlayerCommand.skip).serve((x) => skip(count: x.count));
    p
        .command(PlayerCommand.stop)
        .serve(
          (_) => stop(),
          callers: const Callers({'listener': Access.allow}),
        );
    p
        .query(PlayerQuery.search)
        .serve(
          (x) => search(text: x.text, limit: x.limit),
          askers: const Callers({'*': Access.allow}),
        );
  }

  /// What it set before it was attached, written once it is.
  var _$written = false;
  void _$write() {
    if (_$written) return;
    _$written = true;
    Single.write(volume);
    Single.write(repeat);
    Single.write(playing);
    Keyed.writeAll(speakerLevel);
  }

  /// player.clipped: said by `say`.
  late final PlayerClippedFact clipped = PlayerClippedFact._(this);

  /// player.finished: said by `say`.
  late final PlayerFinishedFact finished = PlayerFinishedFact._(this);

  /// Serves player.volume_set.
  void setVolume({required int volume});

  /// Serves player.play.
  Future<void> play({
    required Track track,
    Repeat repeat = Repeat.off,
    String? on,
  });

  /// Why player.play cannot run now; null when it can.
  String? whyNotPlay();

  /// Serves player.skip.
  int skip({int count = 1});

  /// Serves player.stop.
  void stop();

  /// Answers player.search.
  List<Track> search({required String text, int? limit});
}

/// player.clipped, as [PlayerOwnerBase] says it.
final class PlayerClippedFact {
  PlayerClippedFact._(this._base);
  final PlayerOwnerBase _base;

  /// Says player.clipped; on behalf of [by], when given.
  void say({required int volume, Principal? by}) =>
      _base._$say('player.clipped', _base._$clipped, (volume: volume), by);
}

/// player.finished, as [PlayerOwnerBase] says it.
final class PlayerFinishedFact {
  PlayerFinishedFact._(this._base);
  final PlayerOwnerBase _base;

  /// Says player.finished; on behalf of [by], when given.
  void say(Track track, {Principal? by}) =>
      _base._$say('player.finished', _base._$finished, track, by);
}

/// The words of [Player] as a consumer uses them: what a part
/// that uses them takes, so a stand-in can be given in its
/// place. [PlayerClient] is them over a participant.
abstract interface class IPlayerClient {
  /// player.volume: its value now, and its changes.
  IStateOf<int> get volume;

  /// player.repeat: its value now, and its changes.
  IStateOf<Repeat> get repeat;

  /// player.playing: its value now, and its changes.
  IStateOf<Track?> get playing;

  /// player.speaker_level, by speaker: each value, and its changes.
  IKeyedOf<num> get speakerLevel;

  /// Calls player.volume_set; a call not done throws [CallNotDone].
  Future<void> setVolume({required int volume});

  /// Calls player.play; a call not done throws [CallNotDone].
  Future<void> play({
    required Track track,
    Repeat repeat = Repeat.off,
    String? on,
  });

  /// Calls player.skip; a call not done throws [CallNotDone].
  Future<int> skip({int count = 1});

  /// Calls player.stop; a call not done throws [CallNotDone].
  Future<void> stop();

  /// Asks player.search; a call not done throws [CallNotDone].
  Future<List<Track>> search({required String text, int? limit});

  /// player.clipped: what it says from now on, and its messages.
  IFactOf<PlayerClipped> get clipped;

  /// player.finished: what it says from now on, and its messages.
  IFactOf<Track> get finished;

  /// Whether [word] is there for the participant now, as this code was built
  /// against it: `WordMismatch`, saying where, when not (SPEC §6.5).
  WordStatus status(IWord word);

  /// [status], then whenever it changes.
  Stream<WordStatus> statusChanges(IWord word);

  /// Each word of [Player] there but not as this code was built against,
  /// with where it breaks; empty when all keep their promises. For a
  /// start in development: `assert(client.mismatches.isEmpty)`.
  Map<String, List<WordBreak>> get mismatches;
}

/// The words of [Player] through a participant, here or across
/// a connection. Made, it tells the registry the code was
/// built against them, for it to say where one is defined
/// otherwise (SPEC §6.9).
final class PlayerClient implements IPlayerClient {
  PlayerClient(IParticipant participant)
    : _$words = GeneratedWords(participant) {
    _$words.builtAgainst(playerWords.words, from: playerWords.from);
  }

  /// The words through the participant [owner] is attached to,
  /// for an owner that uses them: made in its constructor, its
  /// streams heard (`hear`, `listen`) once it is attached.
  PlayerClient.of(IOwner owner) : _$words = GeneratedWords.of(owner) {
    _$words.builtAgainst(playerWords.words, from: playerWords.from);
  }

  final GeneratedWords _$words;

  @override
  IStateOf<int> get volume => _$words.stateOf(PlayerState.volume);

  @override
  IStateOf<Repeat> get repeat => _$words.stateOf(PlayerState.repeat);

  @override
  IStateOf<Track?> get playing => _$words.stateOf(PlayerState.playing);

  @override
  IKeyedOf<num> get speakerLevel => _$words.keyedOf(PlayerState.speakerLevel);

  @override
  Future<void> setVolume({required int volume}) async {
    final r = await _$words.command(PlayerCommand.setVolume).call((
      volume: volume,
    ));
    if (r case CallDone(:final value)) return value;
    throw CallNotDone(r);
  }

  @override
  Future<void> play({
    required Track track,
    Repeat repeat = Repeat.off,
    String? on,
  }) async {
    final r = await _$words.command(PlayerCommand.play).call((
      track: track,
      repeat: repeat,
      on: on,
    ));
    if (r case CallDone(:final value)) return value;
    throw CallNotDone(r);
  }

  @override
  Future<int> skip({int count = 1}) async {
    final r = await _$words.command(PlayerCommand.skip).call((count: count));
    if (r case CallDone(:final value)) return value;
    throw CallNotDone(r);
  }

  @override
  Future<void> stop() async {
    final r = await _$words.command(PlayerCommand.stop).call(());
    if (r case CallDone(:final value)) return value;
    throw CallNotDone(r);
  }

  @override
  Future<List<Track>> search({required String text, int? limit}) async {
    final r = await _$words.query(PlayerQuery.search).ask((
      text: text,
      limit: limit,
    ));
    if (r case CallDone(:final value)) return value;
    throw CallNotDone(r);
  }

  @override
  IFactOf<PlayerClipped> get clipped => _$words.factOf(PlayerFact.clipped);

  @override
  IFactOf<Track> get finished => _$words.factOf(PlayerFact.finished);

  @override
  WordStatus status(IWord word) => _$words.status(word);

  @override
  Stream<WordStatus> statusChanges(IWord word) => _$words.statusChanges(word);

  @override
  Map<String, List<WordBreak>> get mismatches =>
      _$words.mismatches(playerWords.words);
}

/// The vocabulary of [Player]: its name and every word, for
/// `main` to grant a participant (`vocabularies:`) and for
/// `schemaOf`.
const playerWords = WordSet(
  'player',
  [
    ...PlayerState.values,
    ...PlayerCommand.values,
    ...PlayerQuery.values,
    ...PlayerFact.values,
  ],
  from: 'parlance_generator',
  dartName: 'playerWords',
);

Map<String, Object?> _$PlayerTrackToJson(Track v) => v.toJson();

typedef PlayerSetVolume = ({int volume});

Map<String, Object?> _$PlayerSetVolumeTo(PlayerSetVolume p) => {
  'volume': p.volume,
};

PlayerSetVolume _$PlayerSetVolumeFrom(Map<String, Object?> m) =>
    (volume: m['volume']! as int);

Object? _$PlayerSetVolumeAt(PlayerSetVolume p, int i) => p.volume;

typedef PlayerPlay = ({Track track, Repeat repeat, String? on});

Map<String, Object?> _$PlayerPlayTo(PlayerPlay p) => {
  'track': p.track,
  'repeat': p.repeat,
  'on': p.on,
};

PlayerPlay _$PlayerPlayFrom(Map<String, Object?> m) => (
  track: m['track']! as Track,
  repeat: (m['repeat'] as Repeat?) ?? Repeat.off,
  on: m['on'] as String?,
);

Object? _$PlayerPlayAt(PlayerPlay p, int i) => switch (i) {
  0 => p.track,
  1 => p.repeat,
  _ => p.on,
};

typedef PlayerSkip = ({int count});

Map<String, Object?> _$PlayerSkipTo(PlayerSkip p) => {'count': p.count};

PlayerSkip _$PlayerSkipFrom(Map<String, Object?> m) =>
    (count: (m['count'] as int?) ?? 1);

Object? _$PlayerSkipAt(PlayerSkip p, int i) => p.count;

typedef PlayerSearch = ({String text, int? limit});

Map<String, Object?> _$PlayerSearchTo(PlayerSearch p) => {
  'text': p.text,
  'limit': p.limit,
};

PlayerSearch _$PlayerSearchFrom(Map<String, Object?> m) =>
    (text: m['text']! as String, limit: m['limit'] as int?);

Object? _$PlayerSearchAt(PlayerSearch p, int i) => switch (i) {
  0 => p.text,
  _ => p.limit,
};

typedef PlayerClipped = ({int volume});

Map<String, Object?> _$PlayerClippedTo(PlayerClipped p) => {'volume': p.volume};

PlayerClipped _$PlayerClippedFrom(Map<String, Object?> m) =>
    (volume: m['volume']! as int);

Object? _$PlayerClippedAt(PlayerClipped p, int i) => p.volume;
