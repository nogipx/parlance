/// What `parlance_generator` reads (SPEC §23): an abstract class that says a
/// module's words, from which it makes their typed enums and shapes. The
/// class is the truth; nothing reads it at run time.
library;

import '../registry/descriptors.dart';

/// A module's words: each member of the class marked [StateWord],
/// [CommandWord], [QueryWord] or [FactWord] is one, named
/// `<vocabulary>.<name>`.
final class Vocabulary {
  const Vocabulary(this.name, {this.owner = true, this.client = true});

  /// The first words of every name: `orders` for `orders.cancel`.
  final String name;

  /// Whether to make `<Class>Owner` too (SPEC §23.4), an owner base with a
  /// handler to write per command and query.
  final bool owner;

  /// Whether to make `<Class>Client` too (SPEC §23.5): the module's words
  /// as a consumer uses them, over any view, here or across a connection.
  final bool client;
}

/// A state: a getter, its type the value's (`int get volume;`).
final class StateWord {
  const StateWord({this.name, this.key, this.readers, this.meta = const {}});

  /// Its name after the vocabulary's; by default the member's in snake case;
  /// `''` names the vocabulary itself (`signal`, beside `signal.raise`).
  final String? name;

  /// The entity kind of its keys, for a keyed state.
  final String? key;

  /// Who may read it, when not the participant's default (SPEC §22.2).
  final Callers? readers;

  /// What editors show of it (`{'label': 'Muted'}`), as its descriptor's.
  final Map<String, Object?> meta;
}

/// A command: a method, its named parameters the params, its return type
/// what it answers (`void` for nothing).
final class CommandWord {
  const CommandWord({
    this.name,
    this.callers,
    this.deadline,
    this.available = false,
    this.meta = const {},
  });
  final String? name;

  /// What editors show of it, as its descriptor's.
  final Map<String, Object?> meta;

  /// Who may call it, when not the participant's default (SPEC §22.2).
  final Callers? callers;

  final Duration? deadline;

  /// Whether it may be unavailable now: the owner base then asks a
  /// `whyNot<Member>()` it writes (SPEC §6.2).
  final bool available;
}

/// A query (SPEC §6.6): a method, its named parameters the params, its
/// return type the answer.
final class QueryWord {
  const QueryWord({
    this.name,
    this.askers,
    this.deadline,
    this.available = false,
    this.meta = const {},
  });
  final String? name;
  final Map<String, Object?> meta;

  /// Who may ask it, when not who may read (SPEC §6.6).
  final Callers? askers;
  final Duration? deadline;
  final bool available;
}

/// A fact: a method returning `void`, its named parameters the payload, or
/// its one positional parameter the payload itself.
final class FactWord {
  const FactWord({
    this.name,
    this.readers,
    this.open = false,
    this.meta = const {},
  });
  final String? name;
  final Map<String, Object?> meta;

  /// Who may hear it, when not the participant's default (SPEC §22.2).
  final Callers? readers;

  /// Whether others may say it too, beside its owner (SPEC §7).
  final bool open;
}

/// The bounds of a number: on a state's getter, a parameter, a field.
final class Range {
  const Range({this.min, this.max});
  final num? min;
  final num? max;
}

/// The most a text, a list or a map holds.
final class Length {
  const Length({required this.max});
  final int max;
}

/// A text that names an entity of [kind] (SPEC §3).
final class Ref {
  const Ref(this.kind);
  final String kind;
}

/// What a parameter or a field of a record is, for people and agents: the
/// description a tool's schema says.
final class Describe {
  const Describe(this.text);
  final String text;
}

/// The name a parameter or a field of a record has in JSON, when not its
/// Dart name (`@FieldName('in') required int ms`).
final class FieldName {
  const FieldName(this.name);
  final String name;
}

/// A record field's default, as JSON: what it is when left out. A record
/// has no defaults of its own; a parameter says its own (`int count = 1`).
final class Default {
  const Default(this.value);
  final Object? value;
}

/// An `int` of milliseconds: a duration (SPEC §2), at most [max].
final class Millis {
  const Millis({this.max});
  final int? max;
}

/// The value of an enum a value added after the code was built reads as
/// (SPEC §25.2), as Avro's reader takes its enum's default: code built
/// before the value came goes on reading (`enum Mode { on, off,
/// @Fallback() other }`). One value of an enum at most.
final class Fallback {
  const Fallback();
}
