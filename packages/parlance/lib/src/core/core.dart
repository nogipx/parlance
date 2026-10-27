import 'dart:async';
import 'dart:collection';

/// Something that can be withdrawn: a claim, a served port, a definition.
abstract interface class IHandle {
  /// Withdraws it; a second call does nothing.
  void dispose();
}

/// Reads a state: its value now, and as it changes (SPEC §21.6).
///
/// A [Cell] in the core, a typed state in the registry.
abstract interface class IStateReader<V> {
  /// The value, or null when there is none.
  V? get value;

  /// Whether there is a committed value.
  bool get has;

  /// The value now, then on every change.
  Stream<V?> watch();
}

/// Writes a state (SPEC §21.6).
///
/// A [CellWriter] in the core, a typed state's writer in the registry.
abstract interface class IStateWriter<V> {
  void set(V value);
  void remove();
}

/// Calls a command and gets its answer; a call that does not answer
/// fails (SPEC §21.6).
///
/// A [Port] in the core, a typed command in the registry.
abstract interface class ICommandCaller<P, R> {
  Future<R> call(P params);
}

/// Says a fact: that something happened (SPEC §21.6).
///
/// A [SignalEmitter] in the core, a typed fact's emitter in the registry.
abstract interface class IFactEmitter<T> {
  void emit(T value);
}

/// Hears facts as they are said (SPEC §21.6).
///
/// A [Signal] in the core, a typed fact in the registry.
abstract interface class IFactListener<T> {
  Stream<T> get stream;
}

final class _Release implements IHandle {
  _Release(this._f);
  void Function()? _f;

  @override
  void dispose() {
    final f = _f;
    _f = null;
    f?.call();
  }
}

/// A cell or a signal a [Hub] commits for.
abstract class _Member {
  Hub get hub;
}

/// Commits the writes of its cells and the emits of its signals in ticks
/// (SPEC §21.1).
///
/// A write or emit outside [batch] is a tick of its own; [batch] makes
/// everything written in it one tick. Every committed change and emit gets
/// the next [seq]. A cell or signal made without a hub has one of its own.
final class Hub {
  /// [onCommit] sees every tick synchronously, before [ticks] delivers it:
  /// for whoever builds its own record of the tick on top.
  Hub({void Function(HubTick tick)? onCommit}) : _onCommit = onCommit;

  final void Function(HubTick tick)? _onCommit;

  int _seq = 0;
  int _depth = 0;
  bool _committing = false;
  final LinkedHashMap<(_Member, Object?), _Write> _pending = LinkedHashMap();
  final List<_Emit> _emits = [];
  final StreamController<HubTick> _ticks = StreamController.broadcast();

  /// The seq of the last commit.
  int get seq => _seq;

  /// Whether writes are waiting for the end of a batch: reads see them.
  bool get writing => _depth > 0 || _committing;

  /// Every tick, in seq order, delivered asynchronously.
  Stream<HubTick> get ticks => _ticks.stream;

  /// Runs [body] synchronously and commits everything it wrote as one tick.
  /// Batches nest; the outermost commits. When [body] throws, nothing it
  /// wrote or said is committed, and the error goes on.
  void batch(void Function() body) {
    // What was waiting before it, to go back to if [body] throws: a batch
    // is committed whole or not at all, never the half written before the
    // throw.
    final before = _pending.isEmpty ? null : LinkedHashMap.of(_pending);
    final emitted = _emits.length;
    _depth++;
    var done = false;
    try {
      final Object? r = (body as dynamic)();
      if (r is Future) {
        throw ArgumentError('a batch is synchronous; write before awaiting');
      }
      done = true;
    } finally {
      if (!done) {
        _pending.clear();
        if (before != null) _pending.addAll(before);
        _emits.length = emitted;
      }
      _depth--;
      if (_depth == 0) _commit();
    }
  }

  void _write(
    _Member m,
    Object? key,
    Object? value,
    bool removed,
    Object? tag,
  ) {
    _pending[(m, key)] = _Write(value, removed, tag);
    _after();
  }

  void _emit(_Member m, Object? value, Object? tag) {
    _emits.add(_Emit(m, value, tag));
    _after();
  }

  void _after() {
    if (_depth == 0 && !_committing) _commit();
  }

  _Write? _waiting(_Member m, Object? key) =>
      writing ? _pending[(m, key)] : null;

  void _drop(_Member m) {
    _pending.removeWhere((k, _) => identical(k.$1, m));
    _emits.removeWhere((e) => identical(e.member, m));
  }

  void _commit() {
    if (_committing) return;
    _committing = true;
    try {
      while (_pending.isNotEmpty || _emits.isNotEmpty) {
        final writes = [..._pending.entries];
        final emits = [..._emits];
        _pending.clear();
        _emits.clear();
        final changes = <HubChange>[];
        for (final MapEntry(key: (m, key), value: w) in writes) {
          final applied = (m as _Store)._apply(key, w);
          if (applied == null) continue;
          changes.add(
            HubChange._(
              seq: ++_seq,
              store: m,
              key: key,
              value: w.value,
              previous: applied.previous,
              removed: w.removed,
              tag: w.tag,
            ),
          );
        }
        final signals = [
          for (final e in emits)
            HubEmit._(
              seq: ++_seq,
              signal: e.member,
              value: e.value,
              tag: e.tag,
            ),
        ];
        if (changes.isEmpty && signals.isEmpty) continue;
        final tick = HubTick._(
          from: changes.isNotEmpty ? changes.first.seq : signals.first.seq,
          to: _seq,
          changes: List.unmodifiable(changes),
          emits: List.unmodifiable(signals),
        );
        _onCommit?.call(tick);
        if (!_ticks.isClosed) _ticks.add(tick);
      }
    } finally {
      _committing = false;
    }
  }

  /// Closes [ticks].
  Future<void> dispose() => _ticks.close();
}

final class _Write {
  _Write(this.value, this.removed, this.tag);
  final Object? value;
  final bool removed;
  final Object? tag;
}

final class _Emit {
  _Emit(this.member, this.value, this.tag);
  final _Member member;
  final Object? value;
  final Object? tag;
}

/// What a [Hub] committed together.
final class HubTick {
  const HubTick._({
    required this.from,
    required this.to,
    required this.changes,
    required this.emits,
  });

  final int from;
  final int to;
  final List<HubChange> changes;
  final List<HubEmit> emits;
}

/// A committed change of a cell's value.
final class HubChange {
  const HubChange._({
    required this.seq,
    required this.store,
    required this.key,
    required this.value,
    required this.previous,
    required this.removed,
    required this.tag,
  });

  final int seq;

  /// The [Cell] or [KeyedCell] it changed.
  final Object store;

  /// The key of a [KeyedCell]; null for a [Cell].
  final Object? key;
  final Object? value;
  final Object? previous;
  final bool removed;

  /// What the writer gave with the write; the hub never reads it.
  final Object? tag;
}

/// A committed emit of a signal.
final class HubEmit {
  const HubEmit._({
    required this.seq,
    required this.signal,
    required this.value,
    required this.tag,
  });

  final int seq;
  final Object signal;
  final Object? value;
  final Object? tag;
}

abstract class _Store implements _Member {
  ({Object? previous})? _apply(Object? key, _Write w);
}

bool _same(Object? a, Object? b) => a == b;

/// Values by key, written by one writer (SPEC §21.2).
///
/// Reads see the committed values and, inside a batch of its hub, the
/// batch's own writes. A write of an equal value commits nothing.
final class KeyedCell<K, V> implements _Store {
  KeyedCell({Hub? hub, bool Function(V a, V b)? equals})
    : hub = hub ?? Hub(),
      _equals = equals;

  @override
  final Hub hub;
  final bool Function(V a, V b)? _equals;
  final Map<K, V> _values = {};
  KeyedCellWriter<K, V>? _writer;
  bool _closed = false;

  /// Whether a writer holds it now.
  bool get claimed => _writer != null;

  /// The only writer; another claim fails until it is released.
  KeyedCellWriter<K, V> claim() {
    if (_closed) throw StateError('the cell is closed');
    if (_writer != null) throw StateError('the cell has a writer');
    return _writer = KeyedCellWriter._(this);
  }

  /// The value of [key], or null when there is none.
  V? read(K key) {
    if (hub._waiting(this, key) case final w?) {
      return w.removed ? null : w.value as V;
    }
    return _values[key];
  }

  /// Whether [key] has a committed value.
  bool has(K key) => _values.containsKey(key);

  /// The committed values.
  Map<K, V> get values => Map.unmodifiable(_values);

  /// The value of [key] now, then on every committed change.
  Stream<V?> watch(K key) => _watch(this, key, () => read(key));

  /// The value of [key] as a [IStateReader].
  IStateReader<V> at(K key) => _KeyedReader(this, key);

  /// Drops its waiting writes and lets no one write it again.
  void close() {
    _closed = true;
    _writer?._live = false;
    _writer = null;
    hub._drop(this);
  }

  @override
  ({Object? previous})? _apply(Object? key, _Write w) {
    final k = key as K;
    final had = _values.containsKey(k);
    final previous = _values[k];
    if (w.removed) {
      if (!had) return null;
      _values.remove(k);
    } else {
      final value = w.value as V;
      if (had &&
          (_equals?.call(previous as V, value) ?? _same(previous, value))) {
        return null;
      }
      _values[k] = value;
    }
    return (previous: previous);
  }
}

/// The write handle of a [KeyedCell].
final class KeyedCellWriter<K, V> implements IHandle {
  KeyedCellWriter._(this._cell);

  final KeyedCell<K, V> _cell;
  bool _live = true;

  /// Sets the value of [key]; [tag] goes with the change, unread.
  void set(K key, V value, {Object? tag}) {
    _check();
    _cell.hub._write(_cell, key, value, false, tag);
  }

  /// Removes the value of [key].
  void remove(K key, {Object? tag}) {
    _check();
    _cell.hub._write(_cell, key, null, true, tag);
  }

  /// The value of [key] as a [IStateWriter].
  IStateWriter<V> at(K key) => _KeyedWriter(this, key);

  void _check() {
    if (!_live) throw StateError('this writer was released');
  }

  /// Gives the cell up; its values stay.
  @override
  void dispose() {
    if (!_live) return;
    _live = false;
    if (identical(_cell._writer, this)) _cell._writer = null;
  }
}

final class _KeyedReader<K, V> implements IStateReader<V> {
  _KeyedReader(this._cell, this._key);
  final KeyedCell<K, V> _cell;
  final K _key;

  @override
  V? get value => _cell.read(_key);

  @override
  bool get has => _cell.has(_key);

  @override
  Stream<V?> watch() => _cell.watch(_key);
}

final class _KeyedWriter<K, V> implements IStateWriter<V> {
  _KeyedWriter(this._writer, this._key);
  final KeyedCellWriter<K, V> _writer;
  final K _key;

  @override
  void set(V value) => _writer.set(_key, value);

  @override
  void remove() => _writer.remove(_key);
}

/// One value, written by one writer (SPEC §21.2).
final class Cell<V> implements _Store, IStateReader<V> {
  Cell({Hub? hub, bool Function(V a, V b)? equals})
    : hub = hub ?? Hub(),
      _equals = equals;

  @override
  final Hub hub;
  final bool Function(V a, V b)? _equals;
  bool _has = false;
  V? _value;
  CellWriter<V>? _writer;
  bool _closed = false;

  /// Whether a writer holds it now.
  bool get claimed => _writer != null;

  /// The only writer; another claim fails until it is released.
  CellWriter<V> claim() {
    if (_closed) throw StateError('the cell is closed');
    if (_writer != null) throw StateError('the cell has a writer');
    return _writer = CellWriter._(this);
  }

  /// The value, or null when there is none.
  @override
  V? get value {
    if (hub._waiting(this, null) case final w?) {
      return w.removed ? null : w.value as V;
    }
    return _value;
  }

  /// Whether it has a committed value.
  @override
  bool get has => _has;

  /// The value now, then on every committed change.
  @override
  Stream<V?> watch() => _watch(this, null, () => value);

  /// Drops its waiting writes and lets no one write it again.
  void close() {
    _closed = true;
    _writer?._live = false;
    _writer = null;
    hub._drop(this);
  }

  @override
  ({Object? previous})? _apply(Object? key, _Write w) {
    final previous = _value;
    if (w.removed) {
      if (!_has) return null;
      _has = false;
      _value = null;
    } else {
      final value = w.value as V;
      if (_has &&
          (_equals?.call(previous as V, value) ?? _same(previous, value))) {
        return null;
      }
      _has = true;
      _value = value;
    }
    return (previous: previous);
  }
}

/// The write handle of a [Cell].
final class CellWriter<V> implements IHandle, IStateWriter<V> {
  CellWriter._(this._cell);

  final Cell<V> _cell;
  bool _live = true;

  /// Sets the value; [tag] goes with the change, unread.
  @override
  void set(V value, {Object? tag}) {
    _check();
    _cell.hub._write(_cell, null, value, false, tag);
  }

  /// Removes the value.
  @override
  void remove({Object? tag}) {
    _check();
    _cell.hub._write(_cell, null, null, true, tag);
  }

  void _check() {
    if (!_live) throw StateError('this writer was released');
  }

  /// Gives the cell up; its value stays.
  @override
  void dispose() {
    if (!_live) return;
    _live = false;
    if (identical(_cell._writer, this)) _cell._writer = null;
  }
}

Stream<V?> _watch<V>(_Member store, Object? key, V? Function() now) =>
    Stream.multi((out) {
      out.add(now());
      final sub = store.hub.ticks.listen((t) {
        for (final c in t.changes) {
          if (identical(c.store, store) && c.key == key) {
            out.add(c.removed ? null : c.value as V);
          }
        }
      });
      out.onCancel = sub.cancel;
    });

/// What happened, said once, keeping no value (SPEC §21.3).
///
/// One emitter, or as many as claim it when [open].
final class Signal<T> implements _Member, IFactListener<T> {
  Signal({Hub? hub, this.open = false}) : hub = hub ?? Hub();

  @override
  final Hub hub;

  /// Whether more than one emitter may claim it.
  final bool open;
  int _emitters = 0;
  bool _closed = false;

  /// An emitter; a second one fails unless [open].
  SignalEmitter<T> claim() {
    if (_closed) throw StateError('the signal is closed');
    if (!open && _emitters > 0) throw StateError('the signal has an emitter');
    _emitters++;
    return SignalEmitter._(this);
  }

  /// Emits as they are committed.
  @override
  Stream<T> get stream => hub.ticks.expand(
    (t) => [
      for (final e in t.emits)
        if (identical(e.signal, this)) e.value as T,
    ],
  );

  /// Drops its waiting emits and lets no one emit again.
  void close() {
    _closed = true;
    hub._drop(this);
  }
}

/// An emit handle of a [Signal].
final class SignalEmitter<T> implements IHandle, IFactEmitter<T> {
  SignalEmitter._(this._signal);

  final Signal<T> _signal;
  bool _live = true;

  /// Emits [value]; [tag] goes with it, unread.
  @override
  void emit(T value, {Object? tag}) {
    if (!_live || _signal._closed) {
      throw StateError('this emitter was released');
    }
    _signal.hub._emit(_signal, value, tag);
  }

  @override
  void dispose() {
    if (!_live) return;
    _live = false;
    _signal._emitters--;
  }
}

/// Asks the one who serves it, and answers what it answers (SPEC §21.4).
final class Port<P, R> implements ICommandCaller<P, R> {
  FutureOr<R> Function(P params)? _handler;

  /// Whether someone serves it now.
  bool get served => _handler != null;

  /// Serves it with [handler]; another serve fails until this one is
  /// disposed.
  IHandle serve(FutureOr<R> Function(P params) handler) {
    if (_handler != null) throw StateError('the port is served');
    _handler = handler;
    return _Release(() {
      if (identical(_handler, handler)) _handler = null;
    });
  }

  /// What the handler answers; fails when no one serves it.
  @override
  Future<R> call(P params) {
    final h = _handler;
    if (h == null) return Future.error(StateError('no one serves the port'));
    return Future.sync(() => h(params));
  }
}
