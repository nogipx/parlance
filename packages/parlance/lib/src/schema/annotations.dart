/// What `parlance_generator` reads (SPEC §23): an abstract class that says a
/// module's words, from which it makes their typed enums and shapes. The
/// class is the truth; nothing reads it at run time.
library;

import '../registry/descriptors.dart';

/// A module's words: each member of the class marked [StateWord],
/// [CommandWord], [QueryWord] or [FactWord] is one, named
/// `<vocabulary>.<name>`.
final class Vocabulary {
  /// Const constructor; the flags are documented on the fields.
  const Vocabulary(this.name, {this.owner = true, this.client = true});

  /// The first word of every name, one word: `orders` for `orders.cancel`.
  final String name;

  /// Whether to make `<Class>OwnerBase` too (SPEC §23.4), an owner base with a
  /// handler to write per command and query.
  final bool owner;

  /// Whether to make `I<Class>Client` too (SPEC §23.5): the module's words
  /// as a consumer uses them, over any view, here or across a connection.
  final bool client;
}

/// A state: a getter, its type the value's (`int get volume;`).
final class StateWord {
  /// Const constructor; the parameters are documented on the fields.
  const StateWord(
    this.name, {
    this.version,
    this.keyOf,
    this.readers,
    this.meta = const {},
  });

  /// Its name in the vocabulary, always said, so a member renamed in Dart
  /// keeps its word: one word, from a letter, of lower-case letters,
  /// digits, `_` and `-` (`set_light`), no `.`; the word is
  /// `<vocabulary>.<name>`, and `''` names the vocabulary itself (`signal`,
  /// beside `signal.raise`).
  final String name;

  /// Its version past the first: the word is `<vocabulary>.<name>.v<N>`, a
  /// new word beside the old one (SPEC §1).
  final int? version;

  /// The choices its keys are of, for a keyed state: one value per key,
  /// the keys those its owner gives (`choices`), as `@ChoiceOf` names them.
  final String? keyOf;

  /// Who may read it, when not the participant's default (SPEC §22.2).
  final Callers? readers;

  /// What editors show of it (`{'label': 'Muted'}`), as its descriptor's.
  final Map<String, Object?> meta;
}

/// A command: a method, its named parameters the params, its return type
/// what it answers (`void` for nothing).
final class CommandWord {
  /// Const constructor; the parameters are documented on the fields.
  const CommandWord(
    this.name, {
    this.version,
    this.callers,
    this.deadline,
    this.whyNot = false,
    this.meta = const {},
  });

  /// Its name in the vocabulary, always said, so a member renamed in Dart
  /// keeps its word: one word, from a letter, of lower-case letters,
  /// digits, `_` and `-` (`set_light`), no `.`; the word is
  /// `<vocabulary>.<name>`, and `''` names the vocabulary itself (`signal`,
  /// beside `signal.raise`).
  final String name;

  /// Its version past the first: the word is `<vocabulary>.<name>.v<N>`, a
  /// new word beside the old one (SPEC §1).
  final int? version;

  /// What editors show of it, as its descriptor's.
  final Map<String, Object?> meta;

  /// Who may call it, when not the participant's default (SPEC §22.2).
  final Callers? callers;

  /// How long one call may go unanswered before it ends `CallTimedOut` —
  /// it may still happen; `null` for the registry's default.
  final Duration? deadline;

  /// Whether it may not run now: the owner base then asks a
  /// `whyNot<Member>()` it writes (SPEC §6.2).
  final bool whyNot;
}

/// A query (SPEC §6.6): a method, its named parameters the params, its
/// return type the answer.
final class QueryWord {
  /// Const constructor; the parameters are documented on the fields.
  const QueryWord(
    this.name, {
    this.version,
    this.askers,
    this.deadline,
    this.whyNot = false,
    this.meta = const {},
  });

  /// Its name in the vocabulary, always said, so a member renamed in Dart
  /// keeps its word: one word, from a letter, of lower-case letters,
  /// digits, `_` and `-` (`set_light`), no `.`; the word is
  /// `<vocabulary>.<name>`, and `''` names the vocabulary itself (`signal`,
  /// beside `signal.raise`).
  final String name;

  /// Its version past the first: the word is `<vocabulary>.<name>.v<N>`, a
  /// new word beside the old one (SPEC §1).
  final int? version;

  /// What editors show of it, as its descriptor's.
  final Map<String, Object?> meta;

  /// Who may ask it, when not who may read (SPEC §6.6).
  final Callers? askers;

  /// How long one ask may go unanswered before it ends `CallTimedOut`;
  /// `null` for the registry's default.
  final Duration? deadline;

  /// Whether it may not be asked now, as [CommandWord.whyNot] says.
  final bool whyNot;
}

/// A fact: a method returning `void`, its named parameters the payload, or
/// its one positional parameter the payload itself.
final class FactWord {
  /// Const constructor; the parameters are documented on the fields.
  const FactWord(this.name, {this.version, this.readers, this.meta = const {}});

  /// Its name in the vocabulary, always said, so a member renamed in Dart
  /// keeps its word: one word, from a letter, of lower-case letters,
  /// digits, `_` and `-` (`set_light`), no `.`; the word is
  /// `<vocabulary>.<name>`, and `''` names the vocabulary itself (`signal`,
  /// beside `signal.raise`).
  final String name;

  /// Its version past the first: the word is `<vocabulary>.<name>.v<N>`, a
  /// new word beside the old one (SPEC §1).
  final int? version;

  /// What editors show of it, as its descriptor's.
  final Map<String, Object?> meta;

  /// Who may hear it, when not the participant's default (SPEC §22.2).
  final Callers? readers;
}

/// The bounds of a number: on a state's getter, a parameter, a field.
final class Range {
  /// Const constructor.
  const Range({this.min, this.max});

  /// The least it may be.
  final num? min;

  /// The most it may be.
  final num? max;
}

/// The most a text, a list or a map holds.
final class Length {
  /// Const constructor.
  const Length({required this.max});

  /// The most it holds.
  final int max;
}

/// A text that is one of the choices of [of] (SPEC §3), as an owner
/// gives them (`choices(name: of, list: ...)`): a call naming none of them is
/// refused before its handler, and an agent or an editor offers them. On
/// a list, of its items.
final class ChoiceOf {
  /// Const constructor.
  const ChoiceOf(this.of);

  /// The choices it is one of: the `name` of the `choices` that gives them.
  final String of;
}

/// What a parameter or a field of a record is, for people and agents: the
/// description a tool's schema says.
final class Describe {
  /// Const constructor.
  const Describe(this.text);

  /// The description said.
  final String text;
}

/// The name a parameter or a field of a record has in JSON, when not its
/// Dart name (`@FieldName('in') required int ms`).
final class FieldName {
  /// Const constructor.
  const FieldName(this.name);

  /// The name in JSON.
  final String name;
}

/// A record field's default, as JSON: what it is when left out. A record
/// has no defaults of its own; a parameter says its own (`int count = 1`).
final class Default {
  /// Const constructor.
  const Default(this.value);

  /// What it is when left out.
  final Object? value;
}

/// The longest a [Duration] may be (SPEC §2): on a parameter or a field
/// of the type `Duration`, kept as whole milliseconds.
final class Longest {
  /// Const constructor.
  const Longest(this.max);

  /// The longest it may be.
  final Duration max;
}

/// The value of an enum a value added after the code was built reads as
/// (SPEC §25.2), as Avro's reader takes its enum's default: code built
/// before the value came goes on reading (`enum Mode { on, off,
/// @Fallback() other }`). One value of an enum at most.
final class Fallback {
  /// Const constructor.
  const Fallback();
}
