import 'dart:async';

import '../participant/owner.dart' show IOwner, saidApart;
import '../registry/cause.dart';
import '../registry/ids.dart';
import '../registry/messages.dart';
import '../registry/words.dart';

/// A state for a stand-in of a client (SPEC §24): what a test gives a part
/// that takes `I<Class>Client`, its value set by the test.
final class StateStub<T> implements IStateOf<T> {
  StateStub([this._value]);

  T? _value;
  final StreamController<T?> _changed = StreamController.broadcast();

  @override
  T? get value => _value;

  @override
  Stream<T?> get changes => Stream.multi((c) {
    c.add(_value);
    final sub = _changed.stream.listen(c.add);
    c.onCancel = sub.cancel;
  });

  /// Sets its value, as its owner does. Who listens is told.
  void set(T value) {
    _value = value;
    _changed.add(value);
  }

  /// Removes its value: it has none until set again. Who listens is told.
  void remove() {
    _value = null;
    _changed.add(null);
  }
}

/// A keyed state for a stand-in of a client: its values set by the test.
final class KeyedStub<T> implements IKeyedOf<T> {
  KeyedStub([Map<String, T> values = const {}]) : _values = {...values};

  final Map<String, T> _values;
  final StreamController<String> _changed = StreamController.broadcast();

  @override
  T? of(String key) => _values[key];

  @override
  Map<String, T> get all => Map.unmodifiable(_values);

  @override
  Iterable<String> get keys => _values.keys;

  @override
  Stream<T?> changesOf(String key) => Stream.multi((c) {
    c.add(_values[key]);
    final sub = _changed.stream
        .where((k) => k == key)
        .listen((_) => c.add(_values[key]));
    c.onCancel = sub.cancel;
  });

  @override
  Stream<Map<String, T>> get changes => Stream.multi((c) {
    c.add(all);
    final sub = _changed.stream.listen((_) => c.add(all));
    c.onCancel = sub.cancel;
  });

  /// Sets the value of [key], as its owner does. Who listens is told.
  void set(String key, T value) {
    _values[key] = value;
    _changed.add(key);
  }

  /// Removes the value of [key]. Who listens is told.
  void remove(String key) {
    _values.remove(key);
    _changed.add(key);
  }
}

/// A fact for a stand-in of a client: what the test [say]s, heard.
final class FactStub<T> implements IFactOf<T> {
  FactStub({this.name = 'stub.fact', this.by = const Principal('stub')});

  /// The fact's name its messages carry.
  final String name;

  /// On whose behalf it is said.
  final Principal by;

  final StreamController<Fact<T>> _said = StreamController.broadcast();
  var _seq = 0;

  @override
  Stream<T> get payloads => _said.stream.map((f) => f.payload);

  @override
  Stream<Fact<T>> get facts => _said.stream;

  final List<Fact<T>> _all = [];

  @override
  Future<List<Fact<T>>> recent(int count) async =>
      _all.length <= count ? [..._all] : _all.sublist(_all.length - count);

  /// Says [payload]: who listens hears it.
  void say(T payload) {
    final f = Fact(
      payload,
      FactMessage(
        seq: ++_seq,
        id: newId(),
        fact: name,
        payload: payload,
        cause: Cause(by),
        at: DateTime.now(),
      ),
    );
    _all.add(f);
    _said.add(f);
  }
}

/// What [owner] said while it was not attached, each fact's name and
/// payload, in order: an owner made in a test and never attached is its
/// own test double (`expect(saidBy(deck), [('player.clipped', ...)])`).
List<(String, Object?)> saidBy(IOwner owner) => saidApart(owner);
