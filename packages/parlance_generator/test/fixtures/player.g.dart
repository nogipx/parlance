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
        'on': Part(Nullable<String>(Plain(RefType('speaker'))), optional: true),
      },
      to: _$PlayerPlayTo,
      from: _$PlayerPlayFrom,
    ),
    null,
  ),
  skip<PlayerSkip, int>(
    'player.skip',
    RecordShape<PlayerSkip>(
      {'count': Part(Plain(IntType()), defaultValue: 1)},
      to: _$PlayerSkipTo,
      from: _$PlayerSkipFrom,
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
        'limit': Part(Nullable<int>(Plain(IntType())), optional: true),
      },
      to: _$PlayerSearchTo,
      from: _$PlayerSearchFrom,
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
/// writer of each state and an emitter of each fact, and
/// serves each command and query by a handler to write.
abstract base class PlayerOwner extends Owner {
  @override
  Iterable<IWord> get words => PlayerWords.all;

  /// Writes player.volume.
  late final StateWriterOf<int> volume;

  /// Writes player.repeat.
  late final StateWriterOf<Repeat> repeat;

  /// Writes player.playing.
  late final StateWriterOf<Track?> playing;

  /// Writes player.speaker.level.
  late final StateWriterOf<num> speakerLevel;

  /// Says player.clipped.
  late final FactEmitterOf<PlayerClipped> clipped;

  /// Says player.finished.
  late final FactEmitterOf<Track> finished;

  @override
  void define(IParticipant p) {
    volume = keep(p.state(PlayerState.volume).define());
    repeat = keep(p.state(PlayerState.repeat).define());
    playing = keep(p.state(PlayerState.playing).define());
    speakerLevel = keep(p.state(PlayerState.speakerLevel).define());
    clipped = keep(p.fact(PlayerFact.clipped).define());
    finished = keep(p.fact(PlayerFact.finished).define());
    keep(
      p
          .command(PlayerCommand.setVolume)
          .define(setVolume, sets: Sets('player.volume', value: 'volume')),
    );
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

/// Every word of [Player], for `Owner.words` and `schemaOf`.
abstract final class PlayerWords {
  static const List<IWord> all = [
    ...PlayerState.values,
    ...PlayerCommand.values,
    ...PlayerQuery.values,
    ...PlayerFact.values,
  ];
}

Map<String, Object?> _$PlayerTrackToJson(Track v) => v.toJson();

typedef PlayerSetVolume = ({int volume});

Map<String, Object?> _$PlayerSetVolumeTo(PlayerSetVolume p) => {
  'volume': p.volume,
};

PlayerSetVolume _$PlayerSetVolumeFrom(Map<String, Object?> m) =>
    (volume: m['volume']! as int);

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

typedef PlayerSkip = ({int count});

Map<String, Object?> _$PlayerSkipTo(PlayerSkip p) => {'count': p.count};

PlayerSkip _$PlayerSkipFrom(Map<String, Object?> m) =>
    (count: (m['count'] as int?) ?? 1);

typedef PlayerSearch = ({String text, int? limit});

Map<String, Object?> _$PlayerSearchTo(PlayerSearch p) => {
  'text': p.text,
  'limit': p.limit,
};

PlayerSearch _$PlayerSearchFrom(Map<String, Object?> m) =>
    (text: m['text']! as String, limit: m['limit'] as int?);

typedef PlayerClipped = ({int volume});

Map<String, Object?> _$PlayerClippedTo(PlayerClipped p) => {'volume': p.volume};

PlayerClipped _$PlayerClippedFrom(Map<String, Object?> m) =>
    (volume: m['volume']! as int);
