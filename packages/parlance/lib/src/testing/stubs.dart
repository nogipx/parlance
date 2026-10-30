import 'dart:async';

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

  /// Sets its value; null leaves it with none. Who listens is told.
  void set(T? value) {
    _value = value;
    _changed.add(value);
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
  Stream<T?> changesOf(String key) => Stream.multi((c) {
    c.add(_values[key]);
    final sub = _changed.stream
        .where((k) => k == key)
        .listen((_) => c.add(_values[key]));
    c.onCancel = sub.cancel;
  });

  /// Sets the value of [key]; null removes it. Who listens is told.
  void set(String key, T? value) {
    value == null ? _values.remove(key) : _values[key] = value;
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
  Stream<T> get stream => _said.stream.map((f) => f.payload);

  @override
  Stream<Fact<T>> get facts => _said.stream;

  /// Says [payload]: who listens hears it.
  void say(T payload) => _said.add(
    Fact(
      payload,
      FactMessage(
        seq: ++_seq,
        id: newId(),
        fact: name,
        payload: payload,
        cause: Cause(by),
        at: DateTime.now(),
      ),
    ),
  );
}
