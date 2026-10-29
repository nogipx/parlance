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

/// The owner base of [App]: it defines every word, keeps what
/// the owner set of each state and writes it, says each fact
/// by a method of its params, and serves each command and
/// query by a handler of its params. What a handler writes,
/// says and calls follows from the call it serves.
abstract class AppBase implements IOwner {
  AppBase() {
    IOwner.made(this, define: _$define, write: _$write);
  }

  IStateWriterOf<bool>? _$dark;
  bool? _$darkNow;
  var _$darkSet = false;

  /// app.dark, as this owner last set it.
  bool? get dark => _$darkNow;

  /// Sets app.dark; null removes it.
  set dark(bool? value) {
    _$darkNow = value;
    _$darkSet = true;
    value == null ? _$dark?.remove() : _$dark?.set(value);
  }

  void _$define(IParticipant p) {
    _$dark = p.state(AppState.dark).define();
    p.command(AppCommand.toast).serve((x) => toast(text: x.text));
  }

  /// What it set before it was attached, written once it is.
  var _$written = false;
  void _$write() {
    if (_$written) return;
    _$written = true;
    if (_$darkSet) {
      final v = _$darkNow;
      v == null ? _$dark!.remove() : _$dark!.set(v);
    }
  }

  /// Serves app.toast.
  void toast({required String text});
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
/// `LocalView`, a `MirrorView`. Made, it tells the registry
/// the code was built against them, for it to say where one
/// is defined otherwise (SPEC §6.9).
final class AppClient implements IAppClient {
  AppClient(this.view) {
    view.builtAgainst(appWords.words, from: appWords.from);
  }

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
  Map<String, List<WordBreak>> get mismatches =>
      wordMismatches(view, appWords.words);
}

/// The vocabulary of [App]: its name and every word, for
/// `main` to grant a participant (`vocabularies:`) and for
/// `schemaOf`.
const appWords = WordSet('app', [
  ...AppState.values,
  ...AppCommand.values,
], from: 'host_words 1.0.0');

typedef AppToast = ({String text});

Map<String, Object?> _$AppToastTo(AppToast p) => {'text': p.text};

AppToast _$AppToastFrom(Map<String, Object?> m) => (text: m['text']! as String);

Object? _$AppToastAt(AppToast p, int i) => p.text;
