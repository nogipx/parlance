/// What `parlance_generator` reads (SPEC §23): an abstract class that says a
/// module's words, from which it makes their typed enums and shapes. The
/// class is the truth; nothing reads it at run time.
library;

import '../registry/descriptors.dart';

/// A module's words: each member of the class marked [StateWord],
/// [CommandWord], [QueryWord] or [FactWord] is one, named
/// `<namespace>.<name>`.
final class Vocabulary {
  const Vocabulary(this.namespace, {this.owner = true, this.client = true});

  /// The first words of every name: `orders` for `orders.cancel`.
  final String namespace;

  /// Whether to make `<Class>Owner` too (SPEC §23.4), an owner base with a
  /// handler to write per command and query.
  final bool owner;

  /// Whether to make `<Class>Client` too (SPEC §23.5): the module's words
  /// as a consumer uses them, over any view, here or across a connection.
  final bool client;
}

/// A state: a getter, its type the value's (`int get volume;`).
final class StateWord {
  const StateWord({this.name, this.key, this.readers});

  /// Its name after the namespace; by default the member's in snake case.
  final String? name;

  /// The entity kind of its keys, for a keyed state.
  final String? key;

  /// Who may read it, when not the participant's default (SPEC §22.2).
  final Callers? readers;
}

/// A command: a method, its named parameters the params, its return type
/// what it answers (`void` for nothing).
final class CommandWord {
  const CommandWord({
    this.name,
    this.callers,
    this.sets,
    this.setsKey,
    this.setsValue,
    this.interceptable = false,
    this.deadline,
    this.available = false,
  });
  final String? name;

  /// Who may call it, when not the participant's default (SPEC §22.2).
  final Callers? callers;

  /// The state it sets (SPEC §8), by its member in the class; the param
  /// that carries the value is [setsValue] (by default the only one), the
  /// key [setsKey].
  final String? sets;
  final String? setsKey;
  final String? setsValue;

  /// Whether links may run steps before it (SPEC §11).
  final bool interceptable;
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
  });
  final String? name;

  /// Who may ask it, when not who may read (SPEC §6.6).
  final Callers? askers;
  final Duration? deadline;
  final bool available;
}

/// A fact: a method returning `void`, its named parameters the payload, or
/// its one positional parameter the payload itself.
final class FactWord {
  const FactWord({this.name, this.readers});
  final String? name;

  /// Who may hear it, when not the participant's default (SPEC §22.2).
  final Callers? readers;
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
