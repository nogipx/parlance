// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'host_words.dart';

// **************************************************************************
// VocabularyGenerator
// **************************************************************************

/// The states of [App].
enum AppState<T> implements IStateWord<T> {
  dark<bool>('app.dark', PlainShape(BoolType()));

  const AppState(this.name, this.shape, {this.key});
  @override
  final String name;
  @override
  final Shape<T> shape;
  @override
  final String? key;
}

/// The commands of [App].
enum AppCommand<P, R> implements ICommandWord<P, R> {
  toast<AppToast, void>(
    'app.toast',
    RecordShape<AppToast>(
      {'text': Part(PlainShape(TextType(maxLength: 80)))},
      to: _$AppToastTo,
      from: _$AppToastFrom,
      get: _$AppToastAt,
    ),
    null,
  );

  const AppCommand(this.name, this.params, this.returns);
  @override
  final String name;
  @override
  final RecordShape<P> params;
  @override
  final Shape<R>? returns;
}

/// The owner base of [App]: it defines every word, keeps what
/// the owner set of each state and writes it, says each fact
/// by a method of its params, and serves each command and
/// query by a handler of its params. What a handler writes,
/// says and calls follows from the call it serves.
abstract class AppOwnerBase implements IOwner {
  AppOwnerBase() {
    IOwner.made(this, define: _$define, write: _$write, vocabulary: appWords);
  }

  /// app.dark: what this owner set last, read by `value`,
  /// written by `set` and `remove`.
  final Single<bool> dark = Single<bool>();

  void _$define(IParticipant participant) {
    final p = GeneratedWords(participant);
    Single.attach(dark, p.state(AppState.dark).define());
    p.command(AppCommand.toast).serve((x) => toast(text: x.text));
  }

  /// What it set before it was attached, written once it is.
  var _$written = false;
  void _$write() {
    if (_$written) return;
    _$written = true;
    Single.write(dark);
  }

  /// Serves app.toast.
  void toast({required String text});
}

/// The words of [App] as a consumer uses them: what a part
/// that uses them takes, so a stand-in can be given in its
/// place. [AppClient] is them over a participant.
abstract interface class IAppClient {
  /// The words through the participant [owner] is attached to,
  /// for an owner that uses them: made in its constructor, its
  /// streams heard (`hear`, `listen`) once it is attached.
  factory IAppClient.of(IOwner owner) = AppClient._of;

  /// app.dark: its value now, and its changes.
  IStateOf<bool> get dark;

  /// Calls app.toast; a call not done throws [CallNotDone].
  Future<void> toast({required String text});

  /// Whether [word] is there for the participant now, as this code was built
  /// against it: `WordMismatch`, saying where, when not (SPEC §6.5).
  WordStatus status(IWord word);

  /// [status], then whenever it changes.
  Stream<WordStatus> statusChanges(IWord word);

  /// Each word of [App] there but not as this code was built against,
  /// with where it breaks; empty when all keep their promises. For a
  /// start in development: `assert(client.mismatches.isEmpty)`.
  Map<String, List<WordBreak>> get mismatches;
}

/// The words of [App] through a participant, here or across
/// a connection. Made, it tells the registry the code was
/// built against them, for it to say where one is defined
/// otherwise (SPEC §6.9).
final class AppClient implements IAppClient {
  AppClient(IParticipant participant) : _$words = GeneratedWords(participant) {
    _$words.builtAgainst(appWords.words, from: appWords.from);
  }

  AppClient._of(IOwner owner) : _$words = GeneratedWords.of(owner) {
    _$words.builtAgainst(appWords.words, from: appWords.from);
  }

  final GeneratedWords _$words;

  @override
  IStateOf<bool> get dark => _$words.stateOf(AppState.dark);

  @override
  Future<void> toast({required String text}) async {
    final r = await _$words.command(AppCommand.toast).call((text: text));
    if (r case CallDone(:final value)) return value;
    throw CallNotDone(r);
  }

  @override
  WordStatus status(IWord word) => _$words.status(word);

  @override
  Stream<WordStatus> statusChanges(IWord word) => _$words.statusChanges(word);

  @override
  Map<String, List<WordBreak>> get mismatches =>
      _$words.mismatches(appWords.words);
}

/// The vocabulary of [App]: its name and every word, for
/// `main` to grant a participant (`vocabularies:`) and for
/// `schemaOf`.
const appWords = WordSet(
  'app',
  [...AppState.values, ...AppCommand.values],
  from: 'host_words 1.0.0',
  dartName: 'appWords',
);

typedef AppToast = ({String text});

Map<String, Object?> _$AppToastTo(AppToast p) => {'text': p.text};

AppToast _$AppToastFrom(Map<String, Object?> m) => (text: m['text']! as String);

Object? _$AppToastAt(AppToast p, int i) => p.text;
