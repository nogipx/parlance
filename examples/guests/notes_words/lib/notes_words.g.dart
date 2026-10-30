// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'notes_words.dart';

// **************************************************************************
// VocabularyGenerator
// **************************************************************************

/// The states of [Notes].
enum NotesState<T> implements IStateWord<T> {
  all<List<Note>>('notes.all', ListShape(_$NoteShape));

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
      {'text': Part(PlainShape(TextType(maxLength: 200)))},
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

/// The facts of [Notes].
enum NotesFact<T> implements IFactWord<T> {
  added<NotesAdded>(
    'notes.added',
    RecordShape<NotesAdded>(
      {
        'id': Part(PlainShape(TextType())),
        'text': Part(PlainShape(TextType())),
      },
      to: _$NotesAddedTo,
      from: _$NotesAddedFrom,
      get: _$NotesAddedAt,
    ),
  );

  const NotesFact(this.name, this.shape);
  @override
  final String name;
  @override
  final Shape<T> shape;
}

/// The owner base of [Notes]: it defines every word, keeps what
/// the owner set of each state and writes it, says each fact
/// by a method of its params, and serves each command and
/// query by a handler of its params. What a handler writes,
/// says and calls follows from the call it serves.
abstract class NotesOwnerBase implements IOwner {
  NotesOwnerBase() {
    IOwner.made(this, define: _$define, write: _$write, vocabulary: notesWords);
  }

  /// notes.all: what this owner set last, read by `value`,
  /// written by `set` and `remove`.
  final Single<List<Note>> all = Single<List<Note>>();

  IFactSayerOf<NotesAdded>? _$added;

  void _$define(IParticipant participant) {
    final p = GeneratedWords(participant);
    Single.attach(all, p.state(NotesState.all).define());
    _$added = p.fact(NotesFact.added).define();
    p.command(NotesCommand.add).serve((x) => add(text: x.text));
  }

  /// What it set before it was attached, written once it is.
  var _$written = false;
  void _$write() {
    if (_$written) return;
    _$written = true;
    Single.write(all);
  }

  /// notes.added: said by `say`.
  late final NotesAddedFact added = NotesAddedFact._(this);

  /// Serves notes.add.
  void add({required String text});
}

/// notes.added, as [NotesOwnerBase] says it.
final class NotesAddedFact {
  NotesAddedFact._(this._base);
  final NotesOwnerBase _base;

  /// Says notes.added; on behalf of [by], when given.
  /// Said while its owner is not attached, no one hears it.
  void say({required String id, required String text, Principal? by}) =>
      _base._$added?.say((id: id, text: text), by: by);
}

/// The words of [Notes] as a consumer uses them: what a part
/// that uses them takes, so a stand-in can be given in its
/// place.
abstract interface class INotesClient {
  /// The words through [participant], here or across a connection:
  /// what `main` gives a part that uses them.
  factory INotesClient(IParticipant participant) = _$NotesClient;

  /// The words through the participant [owner] is attached to,
  /// for an owner that uses them: made in its constructor, its
  /// streams heard (`hear`, `listen`) once it is attached.
  factory INotesClient.of(IOwner owner) = _$NotesClient._of;

  /// notes.all: its value now, and its changes.
  IStateOf<List<Note>> get all;

  /// Calls notes.add; a call not done throws [CallNotDone]. [cancel] cancels this call:
  /// once cancelled, it throws [CallNotDone] of `CallCancelled`.
  Future<void> add({required String text, CancellationToken? cancel});

  /// notes.added: what it says from now on, and its messages.
  IFactOf<NotesAdded> get added;

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
final class _$NotesClient implements INotesClient {
  _$NotesClient(IParticipant participant)
    : _$words = GeneratedWords(participant) {
    _$words.builtAgainst(notesWords.words, from: notesWords.from);
  }

  _$NotesClient._of(IOwner owner) : _$words = GeneratedWords.of(owner) {
    _$words.builtAgainst(notesWords.words, from: notesWords.from);
  }

  final GeneratedWords _$words;

  @override
  IStateOf<List<Note>> get all => _$words.stateOf(NotesState.all);

  @override
  Future<void> add({required String text, CancellationToken? cancel}) async {
    final r = await _$words.command(NotesCommand.add).call((
      text: text,
    ), cancel: cancel);
    if (r case CallDone(:final value)) return value;
    throw CallNotDone(r);
  }

  @override
  IFactOf<NotesAdded> get added => _$words.factOf(NotesFact.added);

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
  [...NotesState.values, ...NotesCommand.values, ...NotesFact.values],
  from: 'notes_words 1.0.0',
  dartName: 'notesWords',
);

const _$NoteShape = RecordShape<Note>(
  {'id': Part(PlainShape(TextType())), 'text': Part(PlainShape(TextType()))},
  to: _$NoteTo,
  from: _$NoteFrom,
  get: _$NoteAt,
);

Map<String, Object?> _$NoteTo(Note v) => {'id': v.id, 'text': v.text};

Note _$NoteFrom(Map<String, Object?> m) =>
    (id: m['id']! as String, text: m['text']! as String);

Object? _$NoteAt(Note v, int i) => switch (i) {
  0 => v.id,
  _ => v.text,
};

typedef NotesAdd = ({String text});

Map<String, Object?> _$NotesAddTo(NotesAdd p) => {'text': p.text};

NotesAdd _$NotesAddFrom(Map<String, Object?> m) => (text: m['text']! as String);

Object? _$NotesAddAt(NotesAdd p, int i) => p.text;

typedef NotesAdded = ({String id, String text});

Map<String, Object?> _$NotesAddedTo(NotesAdded p) => {
  'id': p.id,
  'text': p.text,
};

NotesAdded _$NotesAddedFrom(Map<String, Object?> m) =>
    (id: m['id']! as String, text: m['text']! as String);

Object? _$NotesAddedAt(NotesAdded p, int i) => switch (i) {
  0 => p.id,
  _ => p.text,
};
