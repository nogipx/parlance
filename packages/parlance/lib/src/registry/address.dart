import 'cause.dart';
import 'ids.dart';

/// An exact target and a portable vocabulary-qualified word name.
final class WordAddress {
  /// Creates an address; a target is a whole principal, never an owner.
  WordAddress(this.target, this.word) {
    target.check();
    if (target.owner.isNotEmpty) {
      throw ArgumentError.value(target, 'target', 'use its whole principal');
    }
    checkWordName(word);
    if (word.contains('/')) throw ArgumentError.value(word, 'word');
  }

  /// Parses `kind[/id]/vocabulary.word`; no implicit target exists.
  factory WordAddress.parse(String value) {
    final slash = value.lastIndexOf('/');
    if (slash <= 0 || slash == value.length - 1) {
      throw FormatException('expected target/word: $value');
    }
    return WordAddress(
      Principal.parse(value.substring(0, slash)),
      value.substring(slash + 1),
    );
  }

  /// The principal that publishes this word.
  final Principal target;

  /// The portable word name, independent of deployment.
  final String word;

  @override
  String toString() => '${target.selector}/$word';

  @override
  bool operator ==(Object other) =>
      other is WordAddress && other.target == target && other.word == word;

  @override
  int get hashCode => Object.hash(target, word);
}
