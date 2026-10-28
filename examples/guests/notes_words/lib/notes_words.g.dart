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
      {'text': Part(Plain(TextType(maxLength: 200)))},
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
      {'id': Part(Plain(TextType())), 'text': Part(Plain(TextType()))},
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

/// The owner base of [Notes]: it defines every word, keeps a
/// writer of each state, says each fact by a method of its
/// params, and serves each command and query by a handler to
/// write (`call.inReply`: the cause of what it does in reply).
abstract base class NotesOwner extends Owner {
  /// Writes notes.all.
  late final StateWriterOf<List<Note>> all;
  late final FactEmitterOf<NotesAdded> _added;

  @override
  void define(IParticipant p) {
    all = keep(p.state(NotesState.all).define());
    _added = keep(p.fact(NotesFact.added).define());
    keep(p.command(NotesCommand.add).define(add));
    defineMore(p);
  }

  /// Says notes.added; [cause] as a write's.
  void added({required String id, required String text, Cause? cause}) =>
      _added.emit((id: id, text: text), cause: cause);

  /// What [Notes] does not say: kinds, guards, words named at
  /// run time. After its words are defined.
  void defineMore(IParticipant p) {}

  /// Serves notes.add.
  void add(CommandCallOf<NotesAdd> call);
}

/// The words of [Notes] as a consumer uses them: what a part
/// that uses them takes, so a stand-in can be given in its
/// place. [NotesClient] is them over a view.
abstract interface class INotesClient {
  /// notes.all now.
  List<Note>? get all;

  /// notes.all now, then whenever it changes.
  Stream<List<Note>?> get allChanges;

  /// Calls notes.add; a call not done throws [CallNotDone].
  Future<void> add({required String text});

  /// notes.added, as it is said from now on: what it says.
  Stream<({String id, String text})> get added;
}

/// The words of [Notes] through a view: its participant, a
/// `LocalView`, a `MirrorView`. Made, it tells the registry
/// the code was built against them, for it to say where one
/// is defined otherwise (SPEC §6.9).
final class NotesClient implements INotesClient {
  NotesClient(this.view) {
    view.builtAgainst(notesWords.words, from: notesWords.from);
  }

  final IRegistryView view;

  @override
  List<Note>? get all => view.state(NotesState.all).read();

  @override
  Stream<List<Note>?> get allChanges => view.state(NotesState.all).watch();

  @override
  Future<void> add({required String text}) async {
    final r = await view.command(NotesCommand.add).call((text: text));
    if (r case CallDone(:final value)) return value;
    throw CallNotDone(r);
  }

  @override
  Stream<({String id, String text})> get added =>
      view.fact(NotesFact.added).stream.map((f) => f.payload);

  /// Whether [word] is there for the view now, as this code was built
  /// against it: `WordMismatch`, saying where, when not (SPEC §6.5).
  WordStatus status(IWord word) => wordStatus(view, word);

  /// [status], then whenever it changes.
  Stream<WordStatus> statusChanges(IWord word) => wordStatusChanges(view, word);

  /// Each word of [Notes] there but not as this code was built against,
  /// with where it breaks; empty when all keep their promises. For a
  /// start in development: `assert(client.mismatches.isEmpty)`.
  Map<String, List<WordBreak>> get mismatches =>
      wordMismatches(view, notesWords.words);

  /// notes.added, as it is said from now on: its payload, and
  /// the message (its id, its cause) to follow it from.
  Stream<Fact<NotesAdded>> get addedFacts => view.fact(NotesFact.added).stream;
}

/// The vocabulary of [Notes]: its name and every word, for
/// `main` to grant a participant (`vocabularies:`) and for
/// `schemaOf`.
const notesWords = WordSet('notes', [
  ...NotesState.values,
  ...NotesCommand.values,
  ...NotesFact.values,
], from: 'notes_words 1.0.0');

const _$NoteShape = RecordShape<Note>(
  {'id': Part(Plain(TextType())), 'text': Part(Plain(TextType()))},
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
