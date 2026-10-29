// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'board.dart';

// **************************************************************************
// VocabularyGenerator
// **************************************************************************

/// The states of [Board].
enum BoardState<T> implements IStateWord<T> {
  notes<Note>('note', _$NoteShape, key: 'note'),
  anything<Object?>('note.anything', Plain(AnyType()));

  const BoardState(this.name, this.shape, {this.key});
  @override
  final String name;
  @override
  final Shape<T> shape;
  @override
  final String? key;
}

/// The commands of [Board].
enum BoardCommand<P, R> implements ICommandWord<P, R> {
  put<BoardPut, ({String id})>(
    'note.put',
    RecordShape<BoardPut>(
      {
        'id': Part(
          Plain(TextType()),
          optional: true,
          description: 'Its id; else a new one.',
        ),
        'note': Part(_$NoteShape),
      },
      to: _$BoardPutTo,
      from: _$BoardPutFrom,
      get: _$BoardPutAt,
    ),
    _$BoardPutValueShape,
  ),
  expire<BoardExpire, void>(
    'note.expire',
    RecordShape<BoardExpire>(
      {
        'id': Part(Plain(ChoiceType('note'))),
        'in': Part(Plain(DurationType(max: 60000))),
      },
      to: _$BoardExpireTo,
      from: _$BoardExpireFrom,
      get: _$BoardExpireAt,
    ),
    null,
  ),
  pin<BoardPin, void>(
    'note.pin',
    RecordShape<BoardPin>(
      {'ids': Part(ListShape(Plain(ChoiceType('note')), maxItems: 3))},
      to: _$BoardPinTo,
      from: _$BoardPinFrom,
      get: _$BoardPinAt,
    ),
    null,
  ),
  count<BoardCount, void>(
    'note.count',
    RecordShape<BoardCount>(
      {'readers': Part(Nullable<int>(Plain(IntType())))},
      to: _$BoardCountTo,
      from: _$BoardCountFrom,
      get: _$BoardCountAt,
    ),
    null,
  );

  const BoardCommand(this.name, this.params, this.returns);
  @override
  final String name;
  @override
  final RecordShape<P> params;
  @override
  final Shape<R>? returns;
}

/// The facts of [Board].
enum BoardFact<T> implements IFactWord<T> {
  seen<Note>('note.seen', _$NoteShape);

  const BoardFact(this.name, this.shape);
  @override
  final String name;
  @override
  final Shape<T> shape;
}

/// The kinds of choices [Board] speaks of: what an owner gives by
/// `choices(BoardChoices.note, ...)`.
abstract final class BoardChoices {
  static const String note = 'note';
}

/// The owner base of [Board]: it defines every word, keeps what
/// the owner set of each state and writes it, says each fact
/// by a method of its params, and serves each command and
/// query by a handler of its params. What a handler writes,
/// says and calls follows from the call it serves.
abstract class BoardOwnerBase implements IOwner {
  BoardOwnerBase() {
    IOwner.made(this, define: _$define, write: _$write);
  }

  /// note, by note: what this owner set of each,
  /// read and written as a map is.
  final Keyed<Note> notes = Keyed<Note>();

  IStateWriterOf<Object?>? _$anything;
  Object? _$anythingNow;
  var _$anythingSet = false;

  /// note.anything, as this owner last set it.
  Object? get anything => _$anythingNow;

  /// Sets note.anything.
  set anything(Object? value) {
    _$anythingNow = value;
    _$anythingSet = true;
    _$anything?.set(value);
  }

  IFactEmitterOf<Note>? _$seen;

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
    Keyed.attach(notes, p.state(BoardState.notes).define());
    _$anything = p.state(BoardState.anything).define();
    _$seen = p.fact(BoardFact.seen).define();
    p.command(BoardCommand.put).serve((x) => put(id: x.id, note: x.note));
    p.command(BoardCommand.expire).serve((x) => expire(id: x.id, ms: x.ms));
    p.command(BoardCommand.pin).serve((x) => pin(ids: x.ids));
    p.command(BoardCommand.count).serve((x) => count(readers: x.readers));
  }

  /// What it set before it was attached, written once it is.
  var _$written = false;
  void _$write() {
    if (_$written) return;
    _$written = true;
    Keyed.writeAll(notes);
    if (_$anythingSet) _$anything!.set(_$anythingNow);
  }

  /// Says note.seen; on behalf of [by], when given.
  void seen(Note note, {Principal? by}) => _$say('note.seen', _$seen, note, by);

  /// Serves note.put.
  ({String id}) put({String? id, required Note note});

  /// Serves note.expire.
  void expire({required String id, required int ms});

  /// Serves note.pin.
  void pin({required List<String> ids});

  /// Serves note.count.
  void count({required int? readers});
}

/// The words of [Board] as a consumer uses them: what a part
/// that uses them takes, so a stand-in can be given in its
/// place. [BoardClient] is them over a participant.
abstract interface class IBoardClient {
  /// note of [note] now.
  Note? notesOf(String note);

  /// note of every note, by key.
  Map<String, Note> get notesAll;

  /// note of [note] now, then on every change.
  Stream<Note?> notesChanges(String note);

  /// note.anything now.
  Object? get anything;

  /// note.anything now, then whenever it changes.
  Stream<Object?> get anythingChanges;

  /// Calls note.put; a call not done throws [CallNotDone].
  Future<({String id})> put({String? id, required Note note});

  /// Calls note.expire; a call not done throws [CallNotDone].
  Future<void> expire({required String id, required int ms});

  /// Calls note.pin; a call not done throws [CallNotDone].
  Future<void> pin({required List<String> ids});

  /// Calls note.count; a call not done throws [CallNotDone].
  Future<void> count({required int? readers});

  /// note.seen, as it is said from now on: what it says.
  Stream<Note> get seen;
}

/// The words of [Board] through a participant, here or across
/// a connection. Made, it tells the registry the code was
/// built against them, for it to say where one is defined
/// otherwise (SPEC §6.9).
final class BoardClient implements IBoardClient {
  BoardClient(IParticipant participant)
    : _$words = GeneratedWords.of(participant) {
    _$words.builtAgainst(boardWords.words, from: boardWords.from);
  }

  /// The words through the participant [owner] is attached to,
  /// for an owner that uses them: made in its constructor, its
  /// streams heard (`hear`, `listen`) once it is attached.
  BoardClient.of(IOwner owner) : _$words = GeneratedWords.ofOwner(owner) {
    _$words.builtAgainst(boardWords.words, from: boardWords.from);
  }

  final GeneratedWords _$words;

  @override
  Note? notesOf(String note) => _$words.state(BoardState.notes).read(key: note);

  @override
  Map<String, Note> get notesAll => {
    for (final MapEntry(:key, :value)
        in _$words.state(BoardState.notes).readAll().entries)
      ?key: value,
  };

  @override
  Stream<Note?> notesChanges(String note) =>
      _$words.later(() => _$words.state(BoardState.notes).watch(key: note));

  @override
  Object? get anything => _$words.state(BoardState.anything).read();

  @override
  Stream<Object?> get anythingChanges =>
      _$words.later(() => _$words.state(BoardState.anything).watch());

  @override
  Future<({String id})> put({String? id, required Note note}) async {
    final r = await _$words.command(BoardCommand.put).call((
      id: id,
      note: note,
    ));
    if (r case CallDone(:final value)) return value;
    throw CallNotDone(r);
  }

  @override
  Future<void> expire({required String id, required int ms}) async {
    final r = await _$words.command(BoardCommand.expire).call((id: id, ms: ms));
    if (r case CallDone(:final value)) return value;
    throw CallNotDone(r);
  }

  @override
  Future<void> pin({required List<String> ids}) async {
    final r = await _$words.command(BoardCommand.pin).call((ids: ids));
    if (r case CallDone(:final value)) return value;
    throw CallNotDone(r);
  }

  @override
  Future<void> count({required int? readers}) async {
    final r = await _$words.command(BoardCommand.count).call((
      readers: readers,
    ));
    if (r case CallDone(:final value)) return value;
    throw CallNotDone(r);
  }

  @override
  Stream<Note> get seen => _$words.later(
    () => _$words.fact(BoardFact.seen).stream.map((f) => f.payload),
  );

  /// Whether [word] is there for the participant now, as this code was built
  /// against it: `WordMismatch`, saying where, when not (SPEC §6.5).
  WordStatus status(IWord word) => _$words.status(word);

  /// [status], then whenever it changes.
  Stream<WordStatus> statusChanges(IWord word) => _$words.statusChanges(word);

  /// Each word of [Board] there but not as this code was built against,
  /// with where it breaks; empty when all keep their promises. For a
  /// start in development: `assert(client.mismatches.isEmpty)`.
  Map<String, List<WordBreak>> get mismatches =>
      _$words.mismatches(boardWords.words);

  /// note.seen, as it is said from now on: its payload, and
  /// the message (its id, its cause) to follow it from.
  Stream<Fact<Note>> get seenFacts =>
      _$words.later(() => _$words.fact(BoardFact.seen).stream);
}

/// The vocabulary of [Board]: its name and every word, for
/// `main` to grant a participant (`vocabularies:`) and for
/// `schemaOf`.
const boardWords = WordSet('note', [
  ...BoardState.values,
  ...BoardCommand.values,
  ...BoardFact.values,
], from: 'parlance_generator');

const _$ActionShape = RecordShape<Action>(
  {
    'call': Part(Plain(TextType())),
    'params': Part(MapShape(Plain(AnyType())), defaultValue: {}),
  },
  to: _$ActionTo,
  from: _$ActionFrom,
  get: _$ActionAt,
);

Map<String, Object?> _$ActionTo(Action v) => {
  'call': v.call,
  'params': v.params,
};

Action _$ActionFrom(Map<String, Object?> m) => (
  call: m['call']! as String,
  params: (m['params'] as Map<String, Object?>?) ?? {},
);

Object? _$ActionAt(Action v, int i) => switch (i) {
  0 => v.call,
  _ => v.params,
};

const _$NoteShape = RecordShape<Note>(
  {
    'level': Part(EnumShape(Level.values)),
    'text': Part(Plain(TextType(maxLength: 200)), description: 'What it says.'),
    'tags': Part(ListShape(Plain(TextType())), defaultValue: []),
    'by': Part(Plain(TextType()), optional: true),
    'action': Part(_$ActionShape, optional: true),
  },
  to: _$NoteTo,
  from: _$NoteFrom,
  get: _$NoteAt,
);

Map<String, Object?> _$NoteTo(Note v) => {
  'level': v.level,
  'text': v.text,
  'tags': v.tags,
  'by': v.author,
  'action': v.action,
};

Note _$NoteFrom(Map<String, Object?> m) => (
  level: m['level']! as Level,
  text: m['text']! as String,
  tags: (m['tags'] as List<String>?) ?? [],
  author: m['by'] as String?,
  action: m['action'] as Action?,
);

Object? _$NoteAt(Note v, int i) => switch (i) {
  0 => v.level,
  1 => v.text,
  2 => v.tags,
  3 => v.author,
  _ => v.action,
};

typedef BoardPut = ({String? id, Note note});

Map<String, Object?> _$BoardPutTo(BoardPut p) => {'id': p.id, 'note': p.note};

BoardPut _$BoardPutFrom(Map<String, Object?> m) =>
    (id: m['id'] as String?, note: m['note']! as Note);

Object? _$BoardPutAt(BoardPut p, int i) => switch (i) {
  0 => p.id,
  _ => p.note,
};

const _$BoardPutValueShape = RecordShape<({String id})>(
  {'id': Part(Plain(TextType()))},
  to: _$BoardPutValueTo,
  from: _$BoardPutValueFrom,
  get: _$BoardPutValueAt,
);

Map<String, Object?> _$BoardPutValueTo(({String id}) v) => {'id': v.id};

({String id}) _$BoardPutValueFrom(Map<String, Object?> m) =>
    (id: m['id']! as String);

Object? _$BoardPutValueAt(({String id}) v, int i) => v.id;

typedef BoardExpire = ({String id, int ms});

Map<String, Object?> _$BoardExpireTo(BoardExpire p) => {'id': p.id, 'in': p.ms};

BoardExpire _$BoardExpireFrom(Map<String, Object?> m) =>
    (id: m['id']! as String, ms: m['in']! as int);

Object? _$BoardExpireAt(BoardExpire p, int i) => switch (i) {
  0 => p.id,
  _ => p.ms,
};

typedef BoardPin = ({List<String> ids});

Map<String, Object?> _$BoardPinTo(BoardPin p) => {'ids': p.ids};

BoardPin _$BoardPinFrom(Map<String, Object?> m) =>
    (ids: m['ids']! as List<String>);

Object? _$BoardPinAt(BoardPin p, int i) => p.ids;

typedef BoardCount = ({int? readers});

Map<String, Object?> _$BoardCountTo(BoardCount p) => {'readers': p.readers};

BoardCount _$BoardCountFrom(Map<String, Object?> m) =>
    (readers: m['readers'] as int?);

Object? _$BoardCountAt(BoardCount p, int i) => p.readers;
