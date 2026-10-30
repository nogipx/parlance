// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'notes.dart';

// **************************************************************************
// VocabularyGenerator
// **************************************************************************

/// The states of [Notes].
enum NotesState<T> implements IStateWord<T> {
  count<int>('notes.count', Plain(IntType(min: 0)));

  const NotesState(this.name, this.shape, {this.key});
  @override
  final String name;
  @override
  final Shape<T> shape;
  @override
  final String? key;
}

/// The commands of [Notes].
enum NotesCommand<P, R> implements ICommandWord<P, R> {
  add<NotesAdd, void>(
    'notes.add',
    RecordShape<NotesAdd>(
      {'text': Part(Plain(TextType(maxLength: 500)))},
      to: _$NotesAddTo,
      from: _$NotesAddFrom,
      get: _$NotesAddAt,
    ),
    null,
  );

  const NotesCommand(this.name, this.params, this.returns);
  @override
  final String name;
  @override
  final RecordShape<P> params;
  @override
  final Shape<R>? returns;
}

/// The owner base of [Notes]: it defines every word, keeps what
/// the owner set of each state and writes it, says each fact
/// by a method of its params, and serves each command and
/// query by a handler of its params. What a handler writes,
/// says and calls follows from the call it serves.
abstract class NotesOwnerBase implements IOwner {
  NotesOwnerBase() {
    IOwner.made(this, define: _$define, write: _$write, words: notesWords);
  }

  /// notes.count: what this owner set last, read by `value`,
  /// written by `set` and `remove`.
  final Single<int> count = Single<int>();

  void _$define(IParticipant participant) {
    final p = GeneratedWords.of(participant);
    Single.attach(count, p.state(NotesState.count).define());
    p
        .command(NotesCommand.add)
        .serve(
          (x) => add(text: x.text),
          callers: const Callers({'user': Access.allow, 'agent': Access.allow}),
        );
  }

  /// What it set before it was attached, written once it is.
  var _$written = false;
  void _$write() {
    if (_$written) return;
    _$written = true;
    Single.write(count);
  }

  /// Serves notes.add.
  void add({required String text});
}

/// The words of [Notes] as a consumer uses them: what a part
/// that uses them takes, so a stand-in can be given in its
/// place. [NotesClient] is them over a participant.
abstract interface class INotesClient {
  /// notes.count: its value now, and its changes.
  IStateOf<int> get count;

  /// Calls notes.add; a call not done throws [CallNotDone].
  Future<void> add({required String text});

  /// Whether [word] is there for the participant now, as this code was built
  /// against it: `WordMismatch`, saying where, when not (SPEC §6.5).
  WordStatus status(IWord word);

  /// [status], then whenever it changes.
  Stream<WordStatus> statusChanges(IWord word);

  /// Each word of [Notes] there but not as this code was built against,
  /// with where it breaks; empty when all keep their promises. For a
  /// start in development: `assert(client.mismatches.isEmpty)`.
  Map<String, List<WordBreak>> get mismatches;
}

/// The words of [Notes] through a participant, here or across
/// a connection. Made, it tells the registry the code was
/// built against them, for it to say where one is defined
/// otherwise (SPEC §6.9).
final class NotesClient implements INotesClient {
  NotesClient(IParticipant participant)
    : _$words = GeneratedWords.of(participant) {
    _$words.builtAgainst(notesWords.words, from: notesWords.from);
  }

  /// The words through the participant [owner] is attached to,
  /// for an owner that uses them: made in its constructor, its
  /// streams heard (`hear`, `listen`) once it is attached.
  NotesClient.of(IOwner owner) : _$words = GeneratedWords.ofOwner(owner) {
    _$words.builtAgainst(notesWords.words, from: notesWords.from);
  }

  final GeneratedWords _$words;

  @override
  IStateOf<int> get count => _$words.stateOf(NotesState.count);

  @override
  Future<void> add({required String text}) async {
    final r = await _$words.command(NotesCommand.add).call((text: text));
    if (r case CallDone(:final value)) return value;
    throw CallNotDone(r);
  }

  @override
  WordStatus status(IWord word) => _$words.status(word);

  @override
  Stream<WordStatus> statusChanges(IWord word) => _$words.statusChanges(word);

  @override
  Map<String, List<WordBreak>> get mismatches =>
      _$words.mismatches(notesWords.words);
}

/// The vocabulary of [Notes]: its name and every word, for
/// `main` to grant a participant (`vocabularies:`) and for
/// `schemaOf`.
const notesWords = WordSet(
  'notes',
  [...NotesState.values, ...NotesCommand.values],
  from: 'parlance_mcp',
  dartName: 'notesWords',
);

typedef NotesAdd = ({String text});

Map<String, Object?> _$NotesAddTo(NotesAdd p) => {'text': p.text};

NotesAdd _$NotesAddFrom(Map<String, Object?> m) => (text: m['text']! as String);

Object? _$NotesAddAt(NotesAdd p, int i) => p.text;
