import 'cause.dart';
import 'ids.dart';

/// An exact provider and a portable vocabulary-qualified word name.
final class WordAddress {
  /// Creates an address; a provider is a whole principal, never an owner.
  WordAddress(this.provider, this.word) {
    provider.check();
    if (provider.owner.isNotEmpty) {
      throw ArgumentError.value(
        provider,
        'provider',
        'use its whole principal',
      );
    }
    checkWordName(word);
    if (word.contains('/')) throw ArgumentError.value(word, 'word');
  }

  /// Parses `kind[/id]/vocabulary.word`; no implicit provider exists.
  factory WordAddress.parse(String value) {
    final slash = value.lastIndexOf('/');
    if (slash <= 0 || slash == value.length - 1) {
      throw FormatException('expected provider/word: $value');
    }
    return WordAddress(
      Principal.parse(value.substring(0, slash)),
      value.substring(slash + 1),
    );
  }

  /// The principal that publishes this word.
  final Principal provider;

  /// The portable word name, independent of deployment.
  final String word;

  @override
  String toString() => '${provider.selector}/$word';

  @override
  bool operator ==(Object other) =>
      other is WordAddress && other.provider == provider && other.word == word;

  @override
  int get hashCode => Object.hash(provider, word);
}
