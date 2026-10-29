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

  IStateWriterOf<int>? _$volume;
  int? _$volumeNow;
  var _$volumeSet = false;

  /// player.volume, as this owner last set it.
  int? get volume => _$volumeNow;

  /// Sets player.volume; null removes it.
  set volume(int? value) {
    _$volumeNow = value;
    _$volumeSet = true;
    value == null ? _$volume?.remove() : _$volume?.set(value);
  }

  IStateWriterOf<Repeat>? _$repeat;
  Repeat? _$repeatNow;
  var _$repeatSet = false;

  /// player.repeat, as this owner last set it.
  Repeat? get repeat => _$repeatNow;

  /// Sets player.repeat; null removes it.
  set repeat(Repeat? value) {
    _$repeatNow = value;
    _$repeatSet = true;
    value == null ? _$repeat?.remove() : _$repeat?.set(value);
  }

  IStateWriterOf<Track?>? _$playing;
  Track? _$playingNow;
  var _$playingSet = false;

  /// player.playing, as this owner last set it.
  Track? get playing => _$playingNow;

  /// Sets player.playing.
  set playing(Track? value) {
    _$playingNow = value;
    _$playingSet = true;
    _$playing?.set(value);
  }

  /// player.speaker.level, by speaker: what this owner set of each,
  /// read and written as a map is.
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
    final p = GeneratedWords.of(participant);
    _$volume = p
        .state(PlayerState.volume)
        .define(
          meta: const {
            'label': 'Volume',
            'steps': [0, 50, 100],
          },
        );
    _$repeat = p.state(PlayerState.repeat).define();
    _$playing = p.state(PlayerState.playing).define();
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
          available: whyNotPlay,
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
    if (_$volumeSet) {
      final v = _$volumeNow;
      v == null ? _$volume!.remove() : _$volume!.set(v);
    }
    if (_$repeatSet) {
      final v = _$repeatNow;
      v == null ? _$repeat!.remove() : _$repeat!.set(v);
    }
    if (_$playingSet) _$playing!.set(_$playingNow);
    Keyed.writeAll(speakerLevel);
  }

  /// Says player.clipped; on behalf of [by], when given.
  void clipped({required int volume, Principal? by}) =>
      _$say('player.clipped', _$clipped, (volume: volume), by);

  /// Says player.finished; on behalf of [by], when given.
  void finished(Track track, {Principal? by}) =>
      _$say('player.finished', _$finished, track, by);

  /// Serves player.volume.set.
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

/// The words of [Player] as a consumer uses them: what a part
/// that uses them takes, so a stand-in can be given in its
/// place. [PlayerClient] is them over a participant.
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
  Map<String, num> get speakerLevelAll;

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

/// The words of [Player] through a participant, here or across
/// a connection. Made, it tells the registry the code was
/// built against them, for it to say where one is defined
/// otherwise (SPEC §6.9).
final class PlayerClient implements IPlayerClient {
  PlayerClient(IParticipant participant)
    : _$words = GeneratedWords.of(participant) {
    _$words.builtAgainst(playerWords.words, from: playerWords.from);
  }

  /// The words through the participant [owner] is attached to,
  /// for an owner that uses them: made in its constructor, its
  /// streams heard (`hear`, `listen`) once it is attached.
  PlayerClient.of(IOwner owner) : _$words = GeneratedWords.ofOwner(owner) {
    _$words.builtAgainst(playerWords.words, from: playerWords.from);
  }

  final GeneratedWords _$words;

  @override
  int? get volume => _$words.state(PlayerState.volume).read();

  @override
  Stream<int?> get volumeChanges =>
      _$words.later(() => _$words.state(PlayerState.volume).watch());

  @override
  Repeat? get repeat => _$words.state(PlayerState.repeat).read();

  @override
  Stream<Repeat?> get repeatChanges =>
      _$words.later(() => _$words.state(PlayerState.repeat).watch());

  @override
  Track? get playing => _$words.state(PlayerState.playing).read();

  @override
  Stream<Track?> get playingChanges =>
      _$words.later(() => _$words.state(PlayerState.playing).watch());

  @override
  num? speakerLevelOf(String speaker) =>
      _$words.state(PlayerState.speakerLevel).read(key: speaker);

  @override
  Map<String, num> get speakerLevelAll => {
    for (final MapEntry(:key, :value)
        in _$words.state(PlayerState.speakerLevel).readAll().entries)
      ?key: value,
  };

  @override
  Stream<num?> speakerLevelChanges(String speaker) => _$words.later(
    () => _$words.state(PlayerState.speakerLevel).watch(key: speaker),
  );

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
  Stream<({int volume})> get clipped => _$words.later(
    () => _$words.fact(PlayerFact.clipped).stream.map((f) => f.payload),
  );

  @override
  Stream<Track> get finished => _$words.later(
    () => _$words.fact(PlayerFact.finished).stream.map((f) => f.payload),
  );

  /// Whether [word] is there for the participant now, as this code was built
  /// against it: `WordMismatch`, saying where, when not (SPEC §6.5).
  WordStatus status(IWord word) => _$words.status(word);

  /// [status], then whenever it changes.
  Stream<WordStatus> statusChanges(IWord word) => _$words.statusChanges(word);

  /// Each word of [Player] there but not as this code was built against,
  /// with where it breaks; empty when all keep their promises. For a
  /// start in development: `assert(client.mismatches.isEmpty)`.
  Map<String, List<WordBreak>> get mismatches =>
      _$words.mismatches(playerWords.words);

  /// player.clipped, as it is said from now on: its payload, and
  /// the message (its id, its cause) to follow it from.
  Stream<Fact<PlayerClipped>> get clippedFacts =>
      _$words.later(() => _$words.fact(PlayerFact.clipped).stream);

  /// player.finished, as it is said from now on: its payload, and
  /// the message (its id, its cause) to follow it from.
  Stream<Fact<Track>> get finishedFacts =>
      _$words.later(() => _$words.fact(PlayerFact.finished).stream);
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
