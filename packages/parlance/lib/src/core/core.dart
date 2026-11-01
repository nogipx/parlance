import 'dart:async';
import 'dart:collection';

/// Something that can be withdrawn: a claim, a served command, a definition.
abstract interface class IHandle {
  /// Withdraws it; a second call does nothing.
  void dispose();
}

/// A handle that runs [_f] once, when first disposed: the package's own,
/// not exported.
final class Disposer implements IHandle {
  /// The package's own; [_f] runs once, when first disposed.
  Disposer(this._f);
  void Function()? _f;

  @override
  void dispose() {
    final f = _f;
    _f = null;
    f?.call();
  }
}

/// A state or a fact a [LocalHub] commits for.
abstract class _Member {
  LocalHub get hub;

  /// Closed: nothing of it commits again.
  bool get _closed;
}

/// Commits the writes of its states and what its facts say in ticks
/// (SPEC §21.1).
///
/// A write or a saying outside [batch] is a tick of its own; [batch] makes
/// everything written in it one tick. Every committed change and saying gets
/// the next [seq]. A state or fact made without a hub has one of its own.
final class LocalHub {
  /// [onCommit] sees every tick synchronously, before [ticks] delivers it:
  /// for whoever builds its own record of the tick on top.
  LocalHub({void Function(LocalTick tick)? onCommit}) : _onCommit = onCommit;

  final void Function(LocalTick tick)? _onCommit;

  int _seq = 0;
  int _depth = 0;
  bool _committing = false;
  final LinkedHashMap<(_Member, Object?), _Write> _pending = LinkedHashMap();
  final List<_Say> _said = [];
  final StreamController<LocalTick> _ticks = StreamController.broadcast();

  /// The seq of the last commit.
  int get seq => _seq;

  /// Whether writes are waiting for the end of a batch: reads see them.
  bool get writing => _depth > 0 || _committing;

  /// Every tick, in seq order, delivered asynchronously.
  Stream<LocalTick> get ticks => _ticks.stream;

  /// Runs [body] synchronously and commits everything it wrote as one tick.
  /// Batches nest; the outermost commits. When [body] throws, nothing it
  /// wrote or said is committed, and the error goes on.
  void batch(void Function() body) {
    // What was waiting before it, to go back to if [body] throws: a batch
    // is committed whole or not at all, never the half written before the
    // throw.
    final before = _pending.isEmpty ? null : LinkedHashMap.of(_pending);
    final said = _said.isEmpty ? null : List.of(_said);
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
        // What waited for a state or fact closed in [body] stays dropped:
        // nothing commits for what is gone.
        _pending.clear();
        if (before != null) {
          for (final e in before.entries) {
            if (!e.key.$1._closed) _pending[e.key] = e.value;
          }
        }
        _said.clear();
        if (said != null) {
          _said.addAll(said.where((e) => !e.member._closed));
        }
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

  void _say(_Member m, Object? value, Object? tag) {
    _said.add(_Say(m, value, tag));
    _after();
  }

  void _after() {
    if (_depth == 0 && !_committing) _commit();
  }

  _Write? _waiting(_Member m, Object? key) =>
      writing ? _pending[(m, key)] : null;

  /// Removes every value of [m]: those committed, and those waiting.
  void _clear(_Store m, Iterable<Object?> committed, Object? tag) {
    _pending.removeWhere((k, _) => identical(k.$1, m));
    for (final key in committed) {
      _pending[(m, key)] = _Write(null, true, tag);
    }
    _after();
  }

  void _drop(_Member m) {
    _pending.removeWhere((k, _) => identical(k.$1, m));
    _said.removeWhere((e) => identical(e.member, m));
  }

  void _commit() {
    if (_committing) return;
    _committing = true;
    try {
      while (_pending.isNotEmpty || _said.isNotEmpty) {
        final writes = [..._pending.entries];
        final saying = [..._said];
        _pending.clear();
        _said.clear();
        final changes = <LocalStateChange>[];
        for (final MapEntry(key: (m, key), value: w) in writes) {
          final applied = (m as _Store)._apply(key, w);
          if (applied == null) continue;
          changes.add(
            LocalStateChange._(
              seq: ++_seq,
              state: m,
              key: key,
              value: w.value,
              previous: applied.previous,
              removed: w.removed,
              tag: w.tag,
            ),
          );
        }
        final facts = [
          for (final e in saying)
            LocalFactSaid._(
              seq: ++_seq,
              fact: e.member,
              value: e.value,
              tag: e.tag,
            ),
        ];
        if (changes.isEmpty && facts.isEmpty) continue;
        final tick = LocalTick._(
          from: changes.isNotEmpty ? changes.first.seq : facts.first.seq,
          to: _seq,
          changes: List.unmodifiable(changes),
          facts: List.unmodifiable(facts),
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

final class _Say {
  _Say(this.member, this.value, this.tag);
  final _Member member;
  final Object? value;
  final Object? tag;
}

/// What a [LocalHub] committed together.
final class LocalTick {
  const LocalTick._({
    required this.from,
    required this.to,
    required this.changes,
    required this.facts,
  });

  /// The first tick of it.
  final int from;
  /// The tick after its last.
  final int to;
  /// What changed, in order.
  final List<LocalStateChange> changes;
  /// What was said, in order.
  final List<LocalFactSaid> facts;
}

/// A committed change of a state's value.
final class LocalStateChange {
  const LocalStateChange._({
    required this.seq,
    required this.state,
    required this.key,
    required this.value,
    required this.previous,
    required this.removed,
    required this.tag,
  });

  /// Its place in the hub's total order.
  final int seq;

  /// The [LocalState] or [LocalKeyedState] it changed.
  final Object state;

  /// The key of a [LocalKeyedState]; null for a [LocalState].
  final Object? key;
  /// What it is now; null where [removed].
  final Object? value;
  /// What it was.
  final Object? previous;
  /// Whether the value went.
  final bool removed;

  /// What the writer gave with the write; the hub never reads it.
  final Object? tag;
}

/// What a fact said, committed.
final class LocalFactSaid {
  const LocalFactSaid._({
    required this.seq,
    required this.fact,
    required this.value,
    required this.tag,
  });

  /// Its place in the hub's total order.
  final int seq;
  /// The fact said.
  final Object fact;
  /// The payload said.
  final Object? value;
  /// What the sayer gave with it; the hub never reads it.
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
final class LocalKeyedState<K, V> implements _Store {
  /// One hub of its own, unless [hub] is given; [equals] tells a write
  /// of an equal value from a new one.
  LocalKeyedState({LocalHub? hub, bool Function(V a, V b)? equals})
    : hub = hub ?? LocalHub(),
      _equals = equals;

  @override
  final LocalHub hub;
  final bool Function(V a, V b)? _equals;
  final Map<K, V> _values = {};
  LocalKeyedStateWriter<K, V>? _writer;
  @override
  bool _closed = false;

  /// Whether a writer holds it now.
  bool get claimed => _writer != null;

  /// The only writer; another claim fails until it is released.
  LocalKeyedStateWriter<K, V> claim() {
    if (_closed) throw StateError('the state is closed');
    if (_writer != null) throw StateError('the state has a writer');
    return _writer = LocalKeyedStateWriter._(this);
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

/// The write handle of a [LocalKeyedState].
final class LocalKeyedStateWriter<K, V> implements IHandle {
  LocalKeyedStateWriter._(this._state);

  final LocalKeyedState<K, V> _state;
  bool _live = true;

  /// Sets the value of [key]; [tag] goes with the change, unread.
  void set(K key, V value, {Object? tag}) {
    _check();
    _state.hub._write(_state, key, value, false, tag);
  }

  /// Removes the value of [key].
  void remove(K key, {Object? tag}) {
    _check();
    _state.hub._write(_state, key, null, true, tag);
  }

  /// Removes every value, those committed and those written in the batch
  /// running now: a key written in it and never committed leaves nothing.
  void clear({Object? tag}) {
    _check();
    _state.hub._clear(_state, [..._state._values.keys], tag);
  }

  void _check() {
    if (!_live) throw StateError('this writer was released');
  }

  /// Gives the state up; its values stay.
  @override
  void dispose() {
    if (!_live) return;
    _live = false;
    if (identical(_state._writer, this)) _state._writer = null;
  }
}

/// One value, written by one writer (SPEC §21.2).
final class LocalState<V> implements _Store {
  /// One hub of its own, unless [hub] is given.
  LocalState({LocalHub? hub, bool Function(V a, V b)? equals})
    : hub = hub ?? LocalHub(),
      _equals = equals;

  @override
  final LocalHub hub;
  final bool Function(V a, V b)? _equals;
  bool _has = false;
  V? _value;
  LocalStateWriter<V>? _writer;
  @override
  bool _closed = false;

  /// Whether a writer holds it now.
  bool get claimed => _writer != null;

  /// The only writer; another claim fails until it is released.
  LocalStateWriter<V> claim() {
    if (_closed) throw StateError('the state is closed');
    if (_writer != null) throw StateError('the state has a writer');
    return _writer = LocalStateWriter._(this);
  }

  /// The value, or null when there is none.
  V? get value {
    if (hub._waiting(this, null) case final w?) {
      return w.removed ? null : w.value as V;
    }
    return _value;
  }

  /// Whether it has a committed value.
  bool get has => _has;

  /// The value now, then on every committed change.
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

/// The write handle of a [LocalState].
final class LocalStateWriter<V> implements IHandle {
  LocalStateWriter._(this._state);

  final LocalState<V> _state;
  bool _live = true;

  /// Sets the value; [tag] goes with the change, unread.
  void set(V value, {Object? tag}) {
    _check();
    _state.hub._write(_state, null, value, false, tag);
  }

  /// Removes the value.
  void remove({Object? tag}) {
    _check();
    _state.hub._write(_state, null, null, true, tag);
  }

  void _check() {
    if (!_live) throw StateError('this writer was released');
  }

  /// Gives the state up; its value stays.
  @override
  void dispose() {
    if (!_live) return;
    _live = false;
    if (identical(_state._writer, this)) _state._writer = null;
  }
}

Stream<V?> _watch<V>(_Member state, Object? key, V? Function() now) =>
    Stream.multi((out) {
      out.add(now());
      final sub = state.hub.ticks.listen((t) {
        for (final c in t.changes) {
          if (identical(c.state, state) && c.key == key) {
            out.add(c.removed ? null : c.value as V);
          }
        }
      });
      out.onCancel = sub.cancel;
    });

/// What happened, said once, keeping no value (SPEC §21.3), by its one
/// sayer.
final class LocalFact<T> implements _Member {
  /// One hub of its own, unless [hub] is given.
  LocalFact({LocalHub? hub}) : hub = hub ?? LocalHub();

  @override
  final LocalHub hub;

  int _sayers = 0;
  @override
  bool _closed = false;

  /// Its sayer; a second one fails while the first is held.
  LocalFactSayer<T> claim() {
    if (_closed) throw StateError('the fact is closed');
    if (_sayers > 0) throw StateError('the fact has a sayer');
    _sayers++;
    return LocalFactSayer._(this);
  }

  /// What it says, as it is committed.
  Stream<T> get stream => hub.ticks.expand(
    (t) => [
      for (final e in t.facts)
        if (identical(e.fact, this)) e.value as T,
    ],
  );

  /// Drops what waits to be said and lets no one say again.
  void close() {
    _closed = true;
    hub._drop(this);
  }
}

/// The sayer of a [LocalFact].
final class LocalFactSayer<T> implements IHandle {
  LocalFactSayer._(this._fact);

  final LocalFact<T> _fact;
  bool _live = true;

  /// Says [value]; [tag] goes with it, unread.
  void say(T value, {Object? tag}) {
    if (!_live || _fact._closed) {
      throw StateError('this sayer was released');
    }
    _fact.hub._say(_fact, value, tag);
  }

  @override
  void dispose() {
    if (!_live) return;
    _live = false;
    _fact._sayers--;
  }
}

/// Asks the one who serves it, and answers what it answers (SPEC §21.4).
final class LocalCommand<P, R> {
  FutureOr<R> Function(P params)? _handler;

  /// Whether someone serves it now.
  bool get served => _handler != null;

  /// Serves it with [handler]; another serve fails until this one is
  /// disposed.
  IHandle serve(FutureOr<R> Function(P params) handler) {
    if (_handler != null) throw StateError('the command is served');
    _handler = handler;
    return Disposer(() {
      if (identical(_handler, handler)) _handler = null;
    });
  }

  /// What the handler answers; fails when no one serves it.
  Future<R> call(P params) {
    final h = _handler;
    if (h == null) return Future.error(StateError('no one serves the command'));
    return Future.sync(() => h(params));
  }
}
