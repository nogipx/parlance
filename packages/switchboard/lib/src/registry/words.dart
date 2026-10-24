import 'dart:async';

import 'cause.dart';
import 'descriptors.dart';
import 'messages.dart';
import 'registry.dart';
import 'types.dart';

// Typed words (SPEC §18): a host names its states, commands and facts once,
// with their Dart types, and reads, writes and calls through them. The
// registry underneath keeps names and JSON, as links, remote and agents see
// it.

/// How a value the registry keeps (JSON, checked by [type]) is the Dart
/// type [T].
abstract base class Shape<T> {
  const Shape();

  ValueType<Object?> get type;
  Object? toJson(T value);
  T fromJson(Object? json);
}

/// A value kept as it is: a bool, an int, a num, a text or an entity id.
/// Its Dart type is its type's: `Plain(BoolType())` is a `Shape<bool>`.
final class Plain<T> extends Shape<T> {
  const Plain(this.type);

  @override
  final ValueType<T> type;

  @override
  Object? toJson(T value) => value;

  @override
  T fromJson(Object? json) => json as T;
}

/// One of a Dart enum's [values], kept as its name.
final class EnumShape<E extends Enum> extends Shape<E> {
  const EnumShape(this.values);

  final List<E> values;

  @override
  EnumType get type => EnumType([for (final v in values) v.name]);

  @override
  Object? toJson(E value) => value.name;

  @override
  E fromJson(Object? json) => values.byName(json! as String);
}

/// A list of [item]s.
final class ListShape<T> extends Shape<List<T>> {
  const ListShape(this.item, {this.maxItems});

  final Shape<T> item;
  final int? maxItems;

  @override
  ListType get type => ListType(item.type, maxItems: maxItems);

  @override
  Object? toJson(List<T> value) => [for (final v in value) item.toJson(v)];

  @override
  List<T> fromJson(Object? json) => [
    for (final v in json! as List<Object?>) item.fromJson(v),
  ];
}

/// [of], or null.
final class Nullable<T> extends Shape<T?> {
  const Nullable(this.of);

  final Shape<T> of;

  @override
  NullableType get type => NullableType(of.type);

  @override
  Object? toJson(T? value) => value == null ? null : of.toJson(value);

  @override
  T? fromJson(Object? json) => json == null ? null : of.fromJson(json);
}

/// A map from text to [value]s.
final class MapShape<T> extends Shape<Map<String, T>> {
  const MapShape(this.value, {this.maxEntries});

  final Shape<T> value;
  final int? maxEntries;

  @override
  MapType get type => MapType(value.type, maxEntries: maxEntries);

  @override
  Object? toJson(Map<String, T> v) => {
    for (final e in v.entries) e.key: value.toJson(e.value),
  };

  @override
  Map<String, T> fromJson(Object? json) => {
    for (final e in (json! as Map<Object?, Object?>).entries)
      e.key! as String: value.fromJson(e.value),
  };
}

/// A field of a [RecordShape].
final class Part {
  const Part(
    this.shape, {
    bool optional = false,
    this.defaultValue,
    this.description,
  }) : optional = optional || defaultValue != null;

  /// What it is, for people and agents (a tool's schema says it).
  final String? description;

  final Shape<Object?> shape;

  /// May be left out (its value is then absent); true with a default.
  final bool optional;

  /// What a left-out field becomes, as JSON.
  final Object? defaultValue;
}

/// An object with named [fields], as the Dart type [T] (a record, usually).
///
/// [to] gives a [T]'s fields as Dart values, [from] makes a [T] of them;
/// each field's shape turns its value into JSON and back. Its names are
/// written here, beside the fields, and nowhere else.
final class RecordShape<T> extends Shape<T> {
  const RecordShape(this.fields, {required this.to, required this.from});

  final Map<String, Part> fields;
  final Map<String, Object?> Function(T value) to;
  final T Function(Map<String, Object?> fields) from;

  /// No fields: the params of a command that takes none.
  static const none = RecordShape<()>({}, to: _noFields, from: _unit);

  @override
  ObjectType get type => ObjectType({
    for (final MapEntry(:key, value: p) in fields.entries)
      key: Field(
        p.shape.type,
        optional: p.optional,
        defaultValue: p.defaultValue,
        description: p.description,
      ),
  });

  @override
  Map<String, Object?> toJson(T value) {
    final dart = to(value);
    for (final k in dart.keys) {
      if (!fields.containsKey(k)) throw ArgumentError('no field $k');
    }
    return {
      for (final MapEntry(:key, value: p) in fields.entries)
        // A null a field may be is said: it is a value of its own.
        if (dart[key] != null || (p.shape is Nullable && !p.optional))
          key: p.shape.toJson(dart[key]),
    };
  }

  @override
  T fromJson(Object? json) {
    final m = json! as Map<Object?, Object?>;
    return from({
      for (final MapEntry(:key, value: p) in fields.entries)
        if (m[key] != null) key: p.shape.fromJson(m[key]),
    });
  }

  static Map<String, Object?> _noFields(() _) => const {};
  static () _unit(Map<String, Object?> _) => ();
}

/// One of several objects as the Dart type [T] (a sealed class, usually),
/// told apart by the text in field [key]: each variant is a [RecordShape]
/// of one subtype, named by its tag. [tagOf] names a value's variant.
final class UnionShape<T> extends Shape<T> {
  const UnionShape(
    this.key,
    this.variants, {
    required this.tagOf,
    this.descriptions = const {},
  });

  final String key;
  final Map<String, RecordShape<T>> variants;
  final String Function(T value) tagOf;

  /// What each variant is for, by its tag (a tool's schema says it).
  final Map<String, String> descriptions;

  @override
  OneOfType get type => OneOfType(key, {
    for (final MapEntry(key: tag, value: v) in variants.entries) tag: v.type,
  }, descriptions: descriptions);

  @override
  Map<String, Object?> toJson(T value) {
    final tag = tagOf(value);
    final v = variants[tag] ?? (throw ArgumentError('no variant $tag'));
    return {key: tag, ...v.toJson(value)};
  }

  @override
  T fromJson(Object? json) {
    final m = json! as Map<Object?, Object?>;
    final v = variants[m[key]] ?? (throw FormatException('$key: ${m[key]}'));
    return v.fromJson({
      for (final e in m.entries)
        if (e.key != key) e.key: e.value,
    });
  }
}

/// A state's name, its value's shape and, for a keyed one, the entity kind
/// of its keys. A host's enum of its states implements it.
abstract interface class StateWord<T> {
  String get name;
  Shape<T> get shape;
  String? get key;
}

/// A command's name, its params and what it answers ([returns] null: it
/// answers nothing, and [R] is `void`).
abstract interface class CommandWord<P, R> {
  String get name;
  RecordShape<P> get params;
  Shape<R>? get returns;
}

/// A fact's name and its payload's shape.
abstract interface class FactWord<T> {
  String get name;
  Shape<T> get shape;
}

/// A state's value from its JSON, wherever it was read (a registry, a
/// mirror).
extension StateValues<T> on StateWord<T> {
  T? decode(Object? json) => json == null ? null : shape.fromJson(json);
}

/// A command's answer from what a call ended with, wherever it was called
/// (a registry, a client over remote).
extension CommandAnswers<P, R> on CommandWord<P, R> {
  /// A done call's value decoded as the word says (`failed` when it does
  /// not decode); any other end as it is.
  CallResult<R> answer(CallResult<Object?> raw) {
    if (raw case CallDone(:final value)) {
      try {
        final r = returns;
        return CallDone(r == null ? null as R : r.fromJson(value));
      } on Object catch (e) {
        return CallFailed('the answer is not what $name says: $e');
      }
    }
    return raw as CallResult<R>;
  }
}

/// The registry through typed words. The word fixes the types: a call is
/// made on what `command(word)` gives, so its params can only be the
/// word's.
extension TypedRegistry on Registry {
  StateOf<T> state<T>(StateWord<T> word) => StateOf._(this, word);
  CommandOf<P, R> command<P, R>(CommandWord<P, R> word) =>
      CommandOf._(this, word);
  FactOf<T> fact<T>(FactWord<T> word) => FactOf._(this, word);
}

/// A state, typed.
final class StateOf<T> {
  StateOf._(this.registry, this.word);

  final Registry registry;
  final StateWord<T> word;

  /// Defines it, with [by] its only writer.
  StateWriterOf<T> define({
    required Principal by,
    Callers? readers,
    Map<String, Object?> meta = const {},
  }) => StateWriterOf._(
    registry.defineState(
      StateDescriptor(
        word.name,
        type: word.shape.type,
        key: word.key,
        readers: readers,
        meta: meta,
      ),
      by: by,
    ),
    word.shape,
  );

  T? _decode(Object? json) => word.decode(json);

  /// Its value (of [key]); null when there is none.
  T? read({String? key}) => _decode(registry.read(word.name, key: key));

  bool has({String? key}) => registry.has(word.name, key: key);

  /// Every value, by key.
  Map<String?, T> readAll() => {
    for (final e in registry.readAll(word.name).entries)
      if (e.value != null) e.key: word.shape.fromJson(e.value),
  };

  /// Its value now, then on every change.
  Stream<T?> watch({String? key}) =>
      registry.watch(word.name, key: key).map(_decode);

  /// What it is with its layers on.
  T? effective({String? key}) =>
      _decode(registry.effective(word.name, key: key));
}

/// The only write handle of a typed state.
final class StateWriterOf<T> implements Handle {
  StateWriterOf._(this.raw, this._shape);

  /// The registry's own handle.
  final StateWriter raw;
  final Shape<T> _shape;

  /// As [StateWriter.set].
  void set(T value, {String? key, Cause? cause}) =>
      raw.set(_shape.toJson(value), key: key, cause: cause);

  void remove({String? key, Cause? cause}) =>
      raw.remove(key: key, cause: cause);

  @override
  void dispose() => raw.dispose();
}

/// A call being served, its params typed.
final class CommandCallOf<P> {
  CommandCallOf._(this.raw, this.params);

  /// The call as the registry has it.
  final CommandCall raw;
  final P params;

  String get id => raw.id;
  Cause get cause => raw.cause;
  Principal get by => raw.by;
  Future<void> get expired => raw.expired;
  Cause causeFor(Principal by) => raw.causeFor(by);
}

/// A command, typed.
final class CommandOf<P, R> {
  CommandOf._(this.registry, this.word);

  final Registry registry;
  final CommandWord<P, R> word;

  /// Defines it with its [handler] (SPEC §6.2).
  Handle define(
    FutureOr<R> Function(CommandCallOf<P> call) handler, {
    required Callers callers,
    Sets? sets,
    bool interceptable = false,
    Duration deadline = const Duration(seconds: 30),
    Map<String, Object?> meta = const {},
    Availability? available,
  }) {
    Object? answer(R value) => word.returns?.toJson(value);
    return registry.defineCommand(
      CommandDescriptor(
        word.name,
        params: word.params.type,
        returns: word.returns?.type,
        callers: callers,
        sets: sets,
        interceptable: interceptable,
        deadline: deadline,
        meta: meta,
      ),
      (c) {
        final out = handler(CommandCallOf._(c, word.params.fromJson(c.params)));
        return out is Future<R> ? out.then(answer) : answer(out);
      },
      available: available,
    );
  }

  /// Calls it with [params] on behalf of [by] (SPEC §9).
  Future<CallResult<R>> call(
    P params, {
    required Principal by,
    String? id,
    bool override = false,
    Cause? cause,
  }) async {
    final r = await registry.call(
      word.name,
      word.params.toJson(params),
      by: by,
      id: id,
      override: override,
      cause: cause,
    );
    return word.answer(r);
  }

  /// Why it cannot run now; null when it can.
  String? whyUnavailable() => registry.whyUnavailable(word.name);
}

/// A committed fact, its payload typed.
final class Fact<T> {
  const Fact(this.payload, this.message);

  final T payload;

  /// The fact as the registry has it: id, cause, time.
  final FactMessage message;

  Cause get cause => message.cause;
}

/// A fact, typed.
final class FactOf<T> {
  FactOf._(this.registry, this.word);

  final Registry registry;
  final FactWord<T> word;

  /// Defines it, with [by] its producer.
  FactEmitterOf<T> define({
    required Principal by,
    bool open = false,
    Callers? readers,
    Map<String, Object?> meta = const {},
  }) => FactEmitterOf._(
    registry.defineFact(
      FactDescriptor(
        word.name,
        type: word.shape.type,
        open: open,
        readers: readers,
        meta: meta,
      ),
      by: by,
    ),
    word.shape,
  );

  /// Another producer of an open fact.
  FactEmitterOf<T> producer({required Principal by}) =>
      FactEmitterOf._(registry.producer(word.name, by: by), word.shape);

  Fact<T> _decode(FactMessage m) => Fact(word.shape.fromJson(m.payload), m);

  /// Its facts as they are committed.
  Stream<Fact<T>> get stream => registry.facts(fact: word.name).map(_decode);

  /// The last [n], oldest first.
  List<Fact<T>> recent([int? n]) => [
    for (final m in registry.recent(word.name, n)) _decode(m),
  ];
}

/// An emit handle of a typed fact.
final class FactEmitterOf<T> implements Handle {
  FactEmitterOf._(this.raw, this._shape);

  final FactEmitter raw;
  final Shape<T> _shape;

  /// As [FactEmitter.emit].
  bool emit(T payload, {String? id, Cause? cause}) =>
      raw.emit(_shape.toJson(payload), id: id, cause: cause);

  @override
  void dispose() => raw.dispose();
}
