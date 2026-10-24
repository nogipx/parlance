import 'dart:math';

final Random _random = Random.secure();

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

final RegExp _name = RegExp(r'^[a-z][a-z0-9_-]*(\.[a-z0-9_-]+)*$');

/// Whether [name] is a valid registry name: dotted lower-case words.
bool isValidName(String name) => _name.hasMatch(name);

/// Throws [ArgumentError] unless [name] is a valid registry name.
void checkName(String name, [String what = 'name']) {
  if (!isValidName(name)) {
    throw ArgumentError.value(name, what, 'not a dotted lower-case name');
  }
}
