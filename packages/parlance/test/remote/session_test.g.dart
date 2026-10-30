// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'session_test.dart';

// **************************************************************************
// VocabularyGenerator
// **************************************************************************

/// The owner base of [Plug]: it defines every word, keeps what
/// the owner set of each state and writes it, says each fact
/// by a method of its params, and serves each command and
/// query by a handler of its params. What a handler writes,
/// says and calls follows from the call it serves.
abstract class PlugOwnerBase implements IOwner {
  PlugOwnerBase() {
    IOwner.made(this, define: _$define, write: _$write, vocabulary: plugWords);
  }

  void _$define(IParticipant participant) {}

  /// What it set before it was attached, written once it is.
  var _$written = false;
  void _$write() {
    if (_$written) return;
    _$written = true;
  }
}

/// The words of [Plug] as a consumer uses them: what a part
/// that uses them takes, so a stand-in can be given in its
/// place.
abstract interface class IPlugClient {
  /// The words through [participant], here or across a connection:
  /// what `main` gives a part that uses them.
  factory IPlugClient(IParticipant participant) = _$PlugClient;

  /// The words through the participant [owner] is attached to,
  /// for an owner that uses them: made in its constructor, its
  /// streams heard (`hear`, `listen`) once it is attached.
  factory IPlugClient.of(IOwner owner) = _$PlugClient._of;

  /// Whether [word] is there for the participant now, as this code was built
  /// against it: `WordMismatch`, saying where, when not (SPEC §6.5).
  WordStatus status(IWord word);

  /// [status], then whenever it changes.
  Stream<WordStatus> statusChanges(IWord word);

  /// Each word of [Plug] there but not as this code was built against,
  /// with where it breaks; empty when all keep their promises. For a
  /// start in development: `assert(client.mismatches.isEmpty)`.
  Map<String, List<WordBreak>> get mismatches;
}

/// The words of [Plug] through a participant, here or across
/// a connection. Made, it tells the registry the code was
/// built against them, for it to say where one is defined
/// otherwise (SPEC §6.9).
final class _$PlugClient implements IPlugClient {
  _$PlugClient(IParticipant participant)
    : _$words = GeneratedWords(participant) {
    _$words.builtAgainst(plugWords.words, from: plugWords.from);
  }

  _$PlugClient._of(IOwner owner) : _$words = GeneratedWords.of(owner) {
    _$words.builtAgainst(plugWords.words, from: plugWords.from);
  }

  final GeneratedWords _$words;

  @override
  WordStatus status(IWord word) => _$words.status(word);

  @override
  Stream<WordStatus> statusChanges(IWord word) => _$words.statusChanges(word);

  @override
  Map<String, List<WordBreak>> get mismatches =>
      _$words.mismatches(plugWords.words);
}

/// The vocabulary of [Plug]: its name and every word, for
/// `main` to grant a participant (`vocabularies:`) and for
/// `schemaOf`.
const plugWords = WordSet('plug', [], from: 'parlance', dartName: 'plugWords');
