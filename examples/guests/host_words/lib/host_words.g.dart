// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'host_words.dart';

// **************************************************************************
// VocabularyGenerator
// **************************************************************************

/// The states of [App].
enum AppState<T> implements IStateWord<T> {
  dark<bool>('app.dark', Plain(BoolType()));

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
      {'text': Part(Plain(TextType(maxLength: 80)))},
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

/// The owner base of [App]: it defines every word, keeps a
/// writer of each state, says each fact by a method of its
/// params, and serves each command and query by a handler to
/// write (`call.inReply`: the cause of what it does in reply).
abstract base class AppOwner extends Owner {
  /// Writes app.dark.
  late final StateWriterOf<bool> dark;

  @override
  void define(IParticipant p) {
    dark = keep(p.state(AppState.dark).define());
    keep(p.command(AppCommand.toast).define(toast));
    defineMore(p);
  }

  /// What [App] does not say: kinds, guards, words named at
  /// run time. After its words are defined.
  void defineMore(IParticipant p) {}

  /// Serves app.toast.
  void toast(CommandCallOf<AppToast> call);
}

/// The words of [App] as a consumer uses them: what a part
/// that uses them takes, so a stand-in can be given in its
/// place. [AppClient] is them over a view.
abstract interface class IAppClient {
  /// app.dark now.
  bool? get dark;

  /// app.dark now, then whenever it changes.
  Stream<bool?> get darkChanges;

  /// Calls app.toast; a call not done throws [CallNotDone].
  Future<void> toast({required String text});
}

/// The words of [App] through a view: its participant, a
/// `LocalView`, a `MirrorView`.
final class AppClient implements IAppClient {
  const AppClient(this.view);

  final IRegistryView view;

  @override
  bool? get dark => view.state(AppState.dark).read();

  @override
  Stream<bool?> get darkChanges => view.state(AppState.dark).watch();

  @override
  Future<void> toast({required String text}) async {
    final r = await view.command(AppCommand.toast).call((text: text));
    if (r case CallDone(:final value)) return value;
    throw CallNotDone(r);
  }

  /// Whether [word] is there for the view now, as this code was built
  /// against it: `WordMismatch`, saying where, when not (SPEC §6.5).
  WordStatus status(IWord word) => wordStatus(view, word);

  /// [status], then whenever it changes.
  Stream<WordStatus> statusChanges(IWord word) => wordStatusChanges(view, word);

  /// Each word of [App] there but not as this code was built against,
  /// with where it breaks; empty when all keep their promises. For a
  /// start in development: `assert(client.mismatches.isEmpty)`.
  Map<String, List<String>> get mismatches =>
      wordMismatches(view, appWords.words);
}

/// The vocabulary of [App]: its name and every word, for
/// `main` to grant a participant (`vocabularies:`) and for
/// `schemaOf`.
const appWords = WordSet('app', [...AppState.values, ...AppCommand.values]);

typedef AppToast = ({String text});

Map<String, Object?> _$AppToastTo(AppToast p) => {'text': p.text};

AppToast _$AppToastFrom(Map<String, Object?> m) => (text: m['text']! as String);

Object? _$AppToastAt(AppToast p, int i) => p.text;
