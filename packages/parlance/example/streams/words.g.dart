// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'words.dart';

// **************************************************************************
// VocabularyGenerator
// **************************************************************************

/// The server streams of [Documents].
enum DocumentsServerStream<P, T> implements IServerStreamWord<P, T> {
  read<DocumentsRead, String>(
    'documents.read',
    RecordShape<DocumentsRead>(
      {'name': Part(PlainShape(TextType()))},
      to: _$DocumentsReadTo,
      from: _$DocumentsReadFrom,
      get: _$DocumentsReadAt,
    ),
    PlainShape(TextType()),
  );

  const DocumentsServerStream(this.name, this.params, this.shape);
  @override
  final String name;
  @override
  final RecordShape<P> params;
  @override
  final Shape<T> shape;
}

/// The client streams of [Documents].
enum DocumentsClientStream<P, I, T> implements IClientStreamWord<P, I, T> {
  save<DocumentsSave, String, int>(
    'documents.save',
    RecordShape<DocumentsSave>(
      {'name': Part(PlainShape(TextType()))},
      to: _$DocumentsSaveTo,
      from: _$DocumentsSaveFrom,
      get: _$DocumentsSaveAt,
    ),
    PlainShape(TextType()),
    PlainShape(IntType()),
  );

  const DocumentsClientStream(this.name, this.params, this.input, this.returns);
  @override
  final String name;
  @override
  final RecordShape<P> params;
  @override
  final Shape<I> input;
  @override
  final Shape<T> returns;
}

/// The bidi streams of [Documents].
enum DocumentsBidiStream<P, I, T> implements IBidiStreamWord<P, I, T> {
  preview<DocumentsPreview, String, String>(
    'documents.preview',
    RecordShape<DocumentsPreview>(
      {'prefix': Part(PlainShape(TextType()), defaultValue: '')},
      to: _$DocumentsPreviewTo,
      from: _$DocumentsPreviewFrom,
      get: _$DocumentsPreviewAt,
    ),
    PlainShape(TextType()),
    PlainShape(TextType()),
  );

  const DocumentsBidiStream(this.name, this.params, this.input, this.shape);
  @override
  final String name;
  @override
  final RecordShape<P> params;
  @override
  final Shape<I> input;
  @override
  final Shape<T> shape;
}

/// The owner base of [Documents]: it defines every word, keeps what
/// the owner set of each state and writes it, says each fact
/// by a method of its params, and serves each command and
/// query by a handler of its params. What a handler writes,
/// says and calls follows from the call it serves.
abstract class DocumentsOwnerBase implements IOwner {
  DocumentsOwnerBase() {
    IOwner.made(
      this,
      define: _$define,
      write: _$write,
      vocabulary: documentsWords,
    );
  }

  void _$define(IParticipant participant) {
    final p = GeneratedWords(participant);
    p.serverStream(DocumentsServerStream.read).serve((x) => read(name: x.name));
    p
        .clientStream(DocumentsClientStream.save)
        .serve(
          (x, input) => save(input, name: x.name),
          callers: Callers.anyone,
        );
    p
        .bidiStream(DocumentsBidiStream.preview)
        .serve(
          (x, input) => preview(input, prefix: x.prefix),
          callers: Callers.anyone,
        );
  }

  /// What it set before it was attached, written once it is.
  var _$written = false;
  void _$write() {
    if (_$written) return;
    _$written = true;
  }

  /// Provides documents.read for one subscription.
  Stream<String> read({required String name});

  /// Provides documents.save for one subscription.
  Future<int> save(Stream<String> lines, {required String name});

  /// Provides documents.preview for one subscription.
  Stream<String> preview(Stream<String> lines, {String prefix = ''});
}

/// The words of [Documents] as a consumer uses them: what a part
/// that uses them takes, so a stand-in can be given in its
/// place.
abstract interface class IDocumentsClient {
  /// The words through [participant], here or across a connection:
  /// what `main` gives a part that uses them.
  factory IDocumentsClient(IParticipant participant) = _$DocumentsClient;

  /// The words through the participant [owner] is attached to,
  /// for an owner that uses them: made in its constructor, its
  /// streams heard (`hear`, `listen`) once it is attached.
  factory IDocumentsClient.of(IOwner owner) = _$DocumentsClient._of;

  /// documents.read: opens on listen; cancellation ends this operation.
  Stream<String> read({required String name, CancellationToken? cancel});

  /// documents.save: uploads input and returns its result; cancellation ends this operation.
  Future<int> save(
    Stream<String> lines, {
    required String name,
    CancellationToken? cancel,
  });

  /// documents.preview: opens on listen; cancellation ends this operation.
  Stream<String> preview(
    Stream<String> lines, {
    String prefix = '',
    CancellationToken? cancel,
  });

  /// Whether [word] is there for the participant now, as this code was built
  /// against it: `WordMismatch`, saying where, when not (SPEC §6.5).
  WordStatus status(IWord word);

  /// [status], then whenever it changes.
  Stream<WordStatus> statusChanges(IWord word);

  /// Each word of [Documents] there but not as this code was built against,
  /// with where it breaks; empty when all keep their promises. For a
  /// start in development: `assert(client.mismatches.isEmpty)`.
  Map<String, List<WordBreak>> get mismatches;
}

/// The words of [Documents] through a participant, here or across
/// a connection. Made, it tells the registry the code was
/// built against them, for it to say where one is defined
/// otherwise (SPEC §6.9).
final class _$DocumentsClient implements IDocumentsClient {
  _$DocumentsClient(IParticipant participant)
    : _$words = GeneratedWords(participant) {
    _$words.builtAgainst(documentsWords.words, from: documentsWords.from);
  }

  _$DocumentsClient._of(IOwner owner) : _$words = GeneratedWords.of(owner) {
    _$words.builtAgainst(documentsWords.words, from: documentsWords.from);
  }

  final GeneratedWords _$words;

  @override
  Stream<String> read({required String name, CancellationToken? cancel}) =>
      _$words.serverStream(DocumentsServerStream.read).open((
        name: name,
      ), cancel: cancel);

  @override
  Future<int> save(
    Stream<String> lines, {
    required String name,
    CancellationToken? cancel,
  }) => _$words
      .clientStream(DocumentsClientStream.save)
      .call((name: name), lines, cancel: cancel);

  @override
  Stream<String> preview(
    Stream<String> lines, {
    String prefix = '',
    CancellationToken? cancel,
  }) => _$words
      .bidiStream(DocumentsBidiStream.preview)
      .open((prefix: prefix), lines, cancel: cancel);

  @override
  WordStatus status(IWord word) => _$words.status(word);

  @override
  Stream<WordStatus> statusChanges(IWord word) => _$words.statusChanges(word);

  @override
  Map<String, List<WordBreak>> get mismatches =>
      _$words.mismatches(documentsWords.words);
}

/// The vocabulary of [Documents]: its name and every word, for
/// `main` to grant a participant (`vocabularies:`) and for
/// `schemaOf`.
const documentsWords = WordSet(
  'documents',
  [
    ...DocumentsServerStream.values,
    ...DocumentsClientStream.values,
    ...DocumentsBidiStream.values,
  ],
  from: 'parlance 0.1.3',
  dartName: 'documentsWords',
);

typedef DocumentsRead = ({String name});

Map<String, Object?> _$DocumentsReadTo(DocumentsRead p) => {'name': p.name};

DocumentsRead _$DocumentsReadFrom(Map<String, Object?> m) =>
    (name: m['name']! as String);

Object? _$DocumentsReadAt(DocumentsRead p, int i) => p.name;

typedef DocumentsSave = ({String name});

Map<String, Object?> _$DocumentsSaveTo(DocumentsSave p) => {'name': p.name};

DocumentsSave _$DocumentsSaveFrom(Map<String, Object?> m) =>
    (name: m['name']! as String);

Object? _$DocumentsSaveAt(DocumentsSave p, int i) => p.name;

typedef DocumentsPreview = ({String prefix});

Map<String, Object?> _$DocumentsPreviewTo(DocumentsPreview p) => {
  'prefix': p.prefix,
};

DocumentsPreview _$DocumentsPreviewFrom(Map<String, Object?> m) =>
    (prefix: (m['prefix'] as String?) ?? '');

Object? _$DocumentsPreviewAt(DocumentsPreview p, int i) => p.prefix;
