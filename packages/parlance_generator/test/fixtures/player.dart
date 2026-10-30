import 'package:json_annotation/json_annotation.dart';
import 'package:parlance/schema.dart';

part 'player.g.dart';

/// An unknown way to repeat, one added after this was built, reads as
/// [off].
enum Repeat {
  @Fallback()
  off,
  one,
  all,
}

/// A track, as json_serializable makes one: all the way down to JSON, as
/// parlance takes it.
@JsonSerializable(explicitToJson: true)
final class Track {
  const Track({required this.title, this.seconds, this.artist});
  factory Track.fromJson(Map<String, dynamic> json) => _$TrackFromJson(json);

  final String title;
  @JsonKey(name: 'length')
  final int? seconds;
  final Artist? artist;

  Map<String, dynamic> toJson() => _$TrackToJson(this);
}

@JsonSerializable()
final class Artist {
  const Artist(this.name);
  factory Artist.fromJson(Map<String, dynamic> json) => _$ArtistFromJson(json);
  final String name;
  Map<String, dynamic> toJson() => _$ArtistToJson(this);
}

/// A player's words, written once.
@Vocabulary('player')
abstract class Player {
  @StateWord(
    'volume',
    meta: {
      'label': 'Volume',
      'steps': [0, 50, 100],
    },
  )
  @Range(min: 0, max: 100)
  int get volume;

  @StateWord('repeat')
  Repeat get repeat;

  @StateWord('playing')
  Track? get playing;

  /// Each speaker's level, by speaker.
  @StateWord('speaker_level', keyOf: 'speaker')
  @Range(min: 0, max: 1)
  num get speakerLevel;

  @CommandWord('volume_set')
  void setVolume({@Range(min: 0, max: 100) required int volume});

  /// Cannot play while nothing is loaded.
  @CommandWord('play', whyNot: true, deadline: Duration(seconds: 5))
  Future<void> play({
    required Track track,
    Repeat repeat = Repeat.off,
    @ChoiceOf('speaker') String? on,
  });

  /// Answers how many tracks it skipped.
  @CommandWord('skip')
  int skip({int count = 1});

  @CommandWord('stop', callers: Callers({'listener': Access.allow}))
  void stop();

  @QueryWord('search', askers: Callers({'*': Access.allow}))
  List<Track> search({@Length(max: 40) required String text, int? limit});

  @FactWord('clipped')
  void clipped({required int volume});

  @FactWord('finished')
  void finished(Track track);
}
