part of 'registry.dart';

/// A change in the catalog (SPEC §6.4).
sealed class CatalogChange {
  const CatalogChange();
}

final class DescriptorAdded extends CatalogChange {
  const DescriptorAdded(this.descriptor);
  final Descriptor descriptor;
}

final class DescriptorRemoved extends CatalogChange {
  const DescriptorRemoved(this.descriptor);
  final Descriptor descriptor;
}

/// The choices of [name] came, went or changed.
final class ChoicesChanged extends CatalogChange {
  const ChoicesChanged(this.name);
  final String name;
}

/// A word's old name came or went (SPEC §6.4).
final class AliasChanged extends CatalogChange {
  const AliasChanged(this.alias);
  final String alias;
}

/// The only write handle of a state: the registry's own, or a remote
/// participant's (SPEC §22).
abstract interface class IStateHandle implements IHandle {
  StateDescriptor get descriptor;

  /// The shape whose Dart values [set] takes as they are (SPEC §18); null:
  /// it takes JSON.
  Shape<Object?>? get shape;

  /// Writes [value] (of [key] for a keyed state).
  void set(Object? value, {String? key, Cause? cause});

  void remove({String? key, Cause? cause});
}

/// The sayer of a fact: the registry's own, or a remote participant's
/// (SPEC §22).
abstract interface class IFactHandle implements IHandle {
  FactDescriptor get descriptor;

  /// The shape whose Dart values [say] takes as they are (SPEC §18); null:
  /// it takes JSON.
  Shape<Object?>? get shape;

  /// Says [payload]; false when [id] was said already.
  bool say(Object? payload, {String? id, Cause? cause});
}

/// The only write handle of a state.
final class RawStateWriter implements IStateHandle {
  RawStateWriter._(this._r, this.descriptor, this.by, this.shape);

  final Registry _r;
  @override
  final StateDescriptor descriptor;

  @override
  final Shape<Object?>? shape;

  /// Who writes, for the causes of its writes.
  final Principal by;
  bool _disposed = false;

  /// Sets the value (of [key], for a keyed state).
  ///
  /// A write a handler makes passes [cause] (`call.causeFor(by)`), so it
  /// follows from the call; without it, the write starts a new chain.
  @override
  void set(Object? value, {String? key, Cause? cause}) {
    _live();
    _r._writeState(
      descriptor,
      key,
      value,
      cause ?? Cause(by),
      asIs: shape != null,
    );
  }

  /// Removes the value (of [key]).
  @override
  void remove({String? key, Cause? cause}) {
    _live();
    _r._removeState(descriptor, key, cause ?? Cause(by));
  }

  void _live() {
    if (_disposed) throw StateError('${descriptor.name} is gone');
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _r._undefine(descriptor.name);
  }
}

/// The sayer of a fact.
final class RawFactSayer implements IFactHandle {
  RawFactSayer._(
    this._r,
    this.descriptor,
    this.by,
    this._sayer, {
    required this.definer,
    this.shape,
  });

  final Registry _r;
  final LocalFactSayer<Object?> _sayer;
  @override
  final FactDescriptor descriptor;

  @override
  final Shape<Object?>? shape;

  /// Its owner, for the causes of its facts.
  final Principal by;

  /// Disposing this handle removes the fact from the catalog.
  final bool definer;
  bool _disposed = false;

  /// Emits [payload]. A fact whose [id] was seen within the dedup window is
  /// dropped; returns whether it was taken.
  @override
  bool say(Object? payload, {String? id, Cause? cause}) {
    if (_disposed) throw StateError('${descriptor.name} is gone');
    return _r._say(
      descriptor,
      _sayer,
      payload,
      id ?? newId(),
      cause ?? Cause(by),
      asIs: shape != null,
    );
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _sayer.dispose();
    if (definer) _r._undefine(descriptor.name);
  }
}

final class _StateEntry {
  _StateEntry(this.descriptor, this.local, this.shape) : writer = local.claim();
  final StateDescriptor descriptor;

  /// How its values are checked, kept and told as JSON (SPEC §18).
  final Shape<Object?> shape;

  /// The JSON last told of each key's value, beside the value it is of:
  /// made when asked, once a value.
  final Map<String?, (Object?, Object?)> _json = {};

  /// The JSON of [kept], the value of [key].
  Object? jsonOf(String? key, Object? kept) {
    if (kept == null || shape is JsonValue) return kept;
    if (_json[key] case (final of, final json) when identical(of, kept)) {
      return json;
    }
    final json = freezeJson(shape.toJson(kept));
    _json[key] = (kept, json);
    return json;
  }

  /// Its values by key, null for an unkeyed state; the registry is the
  /// local state's only writer.
  final LocalKeyedState<String?, Object?> local;
  final LocalKeyedStateWriter<String?, Object?> writer;
}

final class _CommandEntry {
  _CommandEntry(
    this.descriptor,
    this.local,
    this.serving,
    this.available, {
    Shape<Object?>? params,
    Shape<Object?>? returns,
  }) : params = params != null && params.keptAsIs
           ? params
           : JsonValue(descriptor.params),
       returns = switch (descriptor.returns) {
         null => null,
         final t =>
           returns != null && returns.keptAsIs ? returns : JsonValue(t),
       };

  /// How its params and its answer are checked and kept (SPEC §18).
  final Shape<Object?> params;
  final Shape<Object?>? returns;

  /// A command's or a query's: both are called through the same stages.
  final CallableDescriptor descriptor;

  bool get query => descriptor is QueryDescriptor;
  final LocalCommand<CommandCall, Object?> local;
  final IHandle serving;
  final Availability? available;
}

final class _FactEntry {
  _FactEntry(this.descriptor, this.local, this.shape);
  final FactDescriptor descriptor;

  /// How its payloads are checked, kept and told as JSON (SPEC §18).
  final Shape<Object?> shape;

  /// Its payloads, tagged with their id and cause.
  final LocalFact<Object?> local;
}

/// The recent facts of one name, and about how much they weigh.
final class _RecentFacts {
  final ListQueue<FactMessage> _q = ListQueue();
  final ListQueue<int> _weights = ListQueue();
  int bytes = 0;

  int get length => _q.length;

  void add(FactMessage f, int weight) {
    _q.add(f);
    _weights.add(weight);
    bytes += weight;
  }

  /// Drops the oldest, and answers it.
  FactMessage removeFirst() {
    bytes -= _weights.removeFirst();
    return _q.removeFirst();
  }

  List<FactMessage> toList() => _q.toList();
}
