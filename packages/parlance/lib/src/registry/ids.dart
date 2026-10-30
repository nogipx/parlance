import 'dart:math';

/// A plain source: an id must be unique, not secret. `Random.secure()`
/// costs 3-6 times as much per id (every write takes one) and is missing
/// in dart2js under Node (no `self.crypto`).
final Random _random = Random();

/// `1 << 32`, as a literal: dart2js shifts are 32-bit, so `1 << 32` is 0
/// in JavaScript and `nextInt(0)` throws.
const int _word = 4294967296;

/// A new message id: 128 random bits as 32 lower-case hex digits.
String newId() {
  final b = StringBuffer();
  for (var i = 0; i < 4; i++) {
    b.write(_random.nextInt(_word).toRadixString(16).padLeft(8, '0'));
  }
  return b.toString();
}

final RegExp _name = RegExp(r'^[a-z][a-z0-9_-]*(\.[a-z][a-z0-9_-]*)*$');

/// Whether [name] is a valid registry name (SPEC §1): lower-case words
/// split by `.`, each from a letter, joined within by `_` or `-`
/// (`house.door.left_open`, `kitten-daycare.lights`); every other sign
/// is reserved.
bool isValidName(String name) => _name.hasMatch(name);

/// Throws [ArgumentError] unless [name] is a valid registry name.
void checkName(String name, [String what = 'name']) {
  if (!isValidName(name)) {
    throw ArgumentError.value(
      name,
      what,
      'lower-case words split by ., each from a letter, joined by _ or -',
    );
  }
}

final RegExp _oneWord = RegExp(r'^[a-z][a-z0-9_-]*$');

/// Whether [name] is a valid name of a vocabulary (SPEC §1): one word of
/// a registry name, no `.`, so a word's name is always
/// `<vocabulary>.<word>[.vN]` and reads one way.
bool isValidVocabularyName(String name) => _oneWord.hasMatch(name);

/// Throws [ArgumentError] unless [name] is a valid name of a vocabulary.
void checkVocabularyName(String name) {
  if (!isValidVocabularyName(name)) {
    throw ArgumentError.value(
      name,
      'vocabulary',
      'one lower-case word from a letter, joined by _ or -, no .',
    );
  }
}

final RegExp _version = RegExp(r'^v(\d+)$');

/// The word a name is a version of, and which version (SPEC §1):
/// `orders.cancel.v2` is version 2 of `orders.cancel`; a name without a
/// version is version 1.
({String word, int version}) wordVersion(String name) {
  final i = name.lastIndexOf('.');
  if (i > 0) {
    if (_version.firstMatch(name.substring(i + 1)) case final m?) {
      return (word: name.substring(0, i), version: int.parse(m[1]!));
    }
  }
  return (word: name, version: 1);
}

/// Throws [ArgumentError] unless [name] is a valid name of a word: a
/// registry name whose version, if it says one, is its last word, `.v2`
/// or later, with no leading zero. Version 1 is the name alone, so a word
/// has one name for it, never two spellings; and a version is only ever
/// the last word, so `orders.v2.cancel` is not read as a version.
void checkWordName(String name, [String what = 'name']) {
  checkName(name, what);
  final words = name.split('.');
  for (final w in words.take(words.length - 1)) {
    if (_version.hasMatch(w)) {
      throw ArgumentError.value(
        name,
        what,
        'a version is the last word only: ${words.where((x) => x != w).join('.')}.$w',
      );
    }
  }
  final last = words.last;
  if (!last.startsWith('v') || !_version.hasMatch(last)) return;
  if (!name.contains('.')) {
    throw ArgumentError.value(name, what, 'a version needs a word before it');
  }
  final n = last.substring(1);
  if (n.startsWith('0')) {
    throw ArgumentError.value(name, what, 'a version has no leading zero');
  }
  if (n == '1') {
    throw ArgumentError.value(
      name,
      what,
      'version 1 is the name alone: ${name.substring(0, name.length - 3)}',
    );
  }
}
