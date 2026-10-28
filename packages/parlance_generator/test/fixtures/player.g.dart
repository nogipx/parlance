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
  repeat<Repeat>('player.repeat', EnumShape(Repeat.values)),
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
    'player.speaker.level',
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
    'player.volume.set',
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
        'repeat': Part(EnumShape(Repeat.values), defaultValue: 'off'),
        'on': Part(Plain(RefType('speaker')), optional: true),
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

/// The owner base of [Player]: it defines every word, keeps a
/// writer of each state, says each fact by a method of its
/// params, and serves each command and query by a handler to
/// write (`call.inReply`: the cause of what it does in reply).
abstract base class PlayerOwner extends Owner {
  /// Writes player.volume.
  late final StateWriterOf<int> volume;

  /// Writes player.repeat.
  late final StateWriterOf<Repeat> repeat;

  /// Writes player.playing.
  late final StateWriterOf<Track?> playing;

  /// Writes player.speaker.level.
  late final StateWriterOf<num> speakerLevel;
  late final FactEmitterOf<PlayerClipped> _clipped;
  late final FactEmitterOf<Track> _finished;

  @override
  void define(IParticipant p) {
    volume = keep(
      p
          .state(PlayerState.volume)
          .define(
            meta: const {
              'label': 'Volume',
              'steps': [0, 50, 100],
            },
          ),
    );
    repeat = keep(p.state(PlayerState.repeat).define());
    playing = keep(p.state(PlayerState.playing).define());
    speakerLevel = keep(p.state(PlayerState.speakerLevel).define());
    _clipped = keep(p.fact(PlayerFact.clipped).define());
    _finished = keep(p.fact(PlayerFact.finished).define());
    keep(p.command(PlayerCommand.setVolume).define(setVolume));
    keep(
      p
          .command(PlayerCommand.play)
          .define(
            play,
            deadline: const Duration(microseconds: 5000000),
            available: whyNotPlay,
          ),
    );
    keep(p.command(PlayerCommand.skip).define(skip));
    keep(
      p
          .command(PlayerCommand.stop)
          .define(stop, callers: const Callers({'listener': Access.allow})),
    );
    keep(
      p
          .query(PlayerQuery.search)
          .define(search, askers: const Callers({'*': Access.allow})),
    );
    defineMore(p);
  }

  /// Says player.clipped; [cause] as a write's.
  void clipped({required int volume, Cause? cause}) =>
      _clipped.emit((volume: volume), cause: cause);

  /// Says player.finished; [cause] as a write's.
  void finished(Track track, {Cause? cause}) =>
      _finished.emit(track, cause: cause);

  /// What [Player] does not say: kinds, guards, words named at
  /// run time. After its words are defined.
  void defineMore(IParticipant p) {}

  /// Serves player.volume.set.
  void setVolume(CommandCallOf<PlayerSetVolume> call);

  /// Serves player.play.
  Future<void> play(CommandCallOf<PlayerPlay> call);

  /// Why player.play cannot run now; null when it can.
  String? whyNotPlay();

  /// Serves player.skip.
  int skip(CommandCallOf<PlayerSkip> call);

  /// Serves player.stop.
  void stop(CommandCallOf<()> call);

  /// Answers player.search.
  List<Track> search(QueryAsk<PlayerSearch> ask);
}

/// The words of [Player] as a consumer uses them: what a part
/// that uses them takes, so a stand-in can be given in its
/// place. [PlayerClient] is them over a view.
abstract interface class IPlayerClient {
  /// player.volume now.
  int? get volume;

  /// player.volume now, then whenever it changes.
  Stream<int?> get volumeChanges;

  /// player.repeat now.
  Repeat? get repeat;

  /// player.repeat now, then whenever it changes.
  Stream<Repeat?> get repeatChanges;

  /// player.playing now.
  Track? get playing;

  /// player.playing now, then whenever it changes.
  Stream<Track?> get playingChanges;

  /// player.speaker.level of [speaker] now.
  num? speakerLevelOf(String speaker);

  /// player.speaker.level of every speaker, by key.
  Map<String?, num> get speakerLevelAll;

  /// player.speaker.level of [speaker] now, then on every change.
  Stream<num?> speakerLevelChanges(String speaker);

  /// Calls player.volume.set; a call not done throws [CallNotDone].
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

  /// player.clipped, as it is said from now on: what it says.
  Stream<({int volume})> get clipped;

  /// player.finished, as it is said from now on: what it says.
  Stream<Track> get finished;
}

/// The words of [Player] through a view: its participant, a
/// `LocalView`, a `MirrorView`. Made, it tells the registry
/// the code was built against them, for it to say where one
/// is defined otherwise (SPEC §6.9).
final class PlayerClient implements IPlayerClient {
  PlayerClient(this.view) {
    view.builtAgainst(playerWords.words, from: playerWords.from);
  }

  final IRegistryView view;

  @override
  int? get volume => view.state(PlayerState.volume).read();

  @override
  Stream<int?> get volumeChanges => view.state(PlayerState.volume).watch();

  @override
  Repeat? get repeat => view.state(PlayerState.repeat).read();

  @override
  Stream<Repeat?> get repeatChanges => view.state(PlayerState.repeat).watch();

  @override
  Track? get playing => view.state(PlayerState.playing).read();

  @override
  Stream<Track?> get playingChanges => view.state(PlayerState.playing).watch();

  @override
  num? speakerLevelOf(String speaker) =>
      view.state(PlayerState.speakerLevel).read(key: speaker);

  @override
  Map<String?, num> get speakerLevelAll =>
      view.state(PlayerState.speakerLevel).readAll();

  @override
  Stream<num?> speakerLevelChanges(String speaker) =>
      view.state(PlayerState.speakerLevel).watch(key: speaker);

  @override
  Future<void> setVolume({required int volume}) async {
    final r = await view.command(PlayerCommand.setVolume).call((
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
    final r = await view.command(PlayerCommand.play).call((
      track: track,
      repeat: repeat,
      on: on,
    ));
    if (r case CallDone(:final value)) return value;
    throw CallNotDone(r);
  }

  @override
  Future<int> skip({int count = 1}) async {
    final r = await view.command(PlayerCommand.skip).call((count: count));
    if (r case CallDone(:final value)) return value;
    throw CallNotDone(r);
  }

  @override
  Future<void> stop() async {
    final r = await view.command(PlayerCommand.stop).call(());
    if (r case CallDone(:final value)) return value;
    throw CallNotDone(r);
  }

  @override
  Future<List<Track>> search({required String text, int? limit}) async {
    final r = await view.query(PlayerQuery.search).ask((
      text: text,
      limit: limit,
    ));
    if (r case CallDone(:final value)) return value;
    throw CallNotDone(r);
  }

  @override
  Stream<({int volume})> get clipped =>
      view.fact(PlayerFact.clipped).stream.map((f) => f.payload);

  @override
  Stream<Track> get finished =>
      view.fact(PlayerFact.finished).stream.map((f) => f.payload);

  /// Whether [word] is there for the view now, as this code was built
  /// against it: `WordMismatch`, saying where, when not (SPEC §6.5).
  WordStatus status(IWord word) => wordStatus(view, word);

  /// [status], then whenever it changes.
  Stream<WordStatus> statusChanges(IWord word) => wordStatusChanges(view, word);

  /// Each word of [Player] there but not as this code was built against,
  /// with where it breaks; empty when all keep their promises. For a
  /// start in development: `assert(client.mismatches.isEmpty)`.
  Map<String, List<WordBreak>> get mismatches =>
      wordMismatches(view, playerWords.words);

  /// player.clipped, as it is said from now on: its payload, and
  /// the message (its id, its cause) to follow it from.
  Stream<Fact<PlayerClipped>> get clippedFacts =>
      view.fact(PlayerFact.clipped).stream;

  /// player.finished, as it is said from now on: its payload, and
  /// the message (its id, its cause) to follow it from.
  Stream<Fact<Track>> get finishedFacts =>
      view.fact(PlayerFact.finished).stream;
}

/// The vocabulary of [Player]: its name and every word, for
/// `main` to grant a participant (`vocabularies:`) and for
/// `schemaOf`.
const playerWords = WordSet('player', [
  ...PlayerState.values,
  ...PlayerCommand.values,
  ...PlayerQuery.values,
  ...PlayerFact.values,
], from: 'parlance_generator');

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
