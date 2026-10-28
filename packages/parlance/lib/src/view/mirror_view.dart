import 'dart:async';

import '../registry/descriptors.dart';
import '../registry/messages.dart';
import '../registry/shapes.dart';
import '../remote/remote.dart';
import 'view.dart';

/// A view of a registry over remote: [mirror] follows its feed, [client]
/// calls. The mirror keeps the states and hears the facts the view's
/// listeners ask for, and no others.
final class MirrorView implements IRegistryView {
  MirrorView(this.mirror, [this.client]);

  final RegistryMirror mirror;

  /// The session's client; after a lost connection, set the new one here
  /// and follow it with the mirror. Null before the first: a call fails.
  ParlanceClient? client;

  final Map<String, int> _states = {};
  final Map<String, int> _facts = {};

  @override
  Object? read(String state, {String? key}) => mirror.read(state, key: key);

  /// Across a connection a value is JSON: decoded, once a value.
  @override
  T? readAs<T>(String state, Shape<T> shape, {String? key}) =>
      decodeWith(shape, read(state, key: key));

  @override
  Map<String?, Object?> readAll(String state) => mirror.readAll(state);

  /// What it keeps for [fetch], as long as it lives.
  final Set<String> _fetched = {};

  @override
  Future<Map<String?, Object?>> fetch(String state, {bool keep = true}) async {
    if (_fetched.contains(state)) {
      await settled;
      return mirror.readAll(state);
    }
    if (keep) _fetched.add(state);
    _want(_states, {state}, 1);
    await settled;
    final values = mirror.readAll(state);
    if (!keep) _want(_states, {state}, -1);
    return values;
  }

  @override
  Stream<void> changes(Set<String> states) {
    late StreamController<void> out;
    StreamSubscription<void>? sub;
    out = StreamController<void>(
      onListen: () {
        _want(_states, states, 1);
        // A tick of any state the mirror keeps, the values a subscription
        // brings, a lost or found connection: each told.
        sub = mirror.changes.listen((_) => out.add(null));
      },
      onCancel: () async {
        _want(_states, states, -1);
        await sub?.cancel();
      },
    );
    return out.stream;
  }

  @override
  Stream<FactMessage> facts(String fact) {
    late StreamController<FactMessage> out;
    StreamSubscription<Tick>? sub;
    out = StreamController<FactMessage>(
      onListen: () {
        _want(_facts, {fact}, 1);
        sub = mirror.ticks.listen((t) {
          // An old name of a fact hears the fact (SPEC §6.4).
          final name = mirror.canonical(fact);
          for (final f in t.facts) {
            if (f.fact == name) out.add(f);
          }
        });
      },
      onCancel: () async {
        _want(_facts, {fact}, -1);
        await sub?.cancel();
      },
    );
    return out.stream;
  }

  @override
  Stream<(T, FactMessage)> factsAs<T>(String fact, Shape<T> shape) =>
      facts(fact).map((m) => (decodeWith(shape, m.payload) as T, m));

  @override
  Future<List<FactMessage>> recent(String fact, int count) async =>
      await client?.recent(fact, count) ?? const [];

  /// Counts who asks for [names] in [wanted]; the mirror subscribes anew
  /// when what anyone asks for changes.
  void _want(Map<String, int> wanted, Set<String> names, int by) {
    var changed = false;
    for (final n in names) {
      final now = (wanted[n] ?? 0) + by;
      if (now <= 0) {
        changed |= wanted.remove(n) != null;
      } else {
        changed |= !wanted.containsKey(n);
        wanted[n] = now;
      }
    }
    if (!changed || _asking) return;
    // What changes in one turn goes in one subscription: a look at many
    // states asks once to add them and once to let them go.
    _asking = true;
    _settled = Future(() {
      _asking = false;
      return mirror
          .subscribe(states: {..._states.keys}, facts: {..._facts.keys})
          .catchError((Object _) {});
    });
  }

  bool _asking = false;

  Future<void>? _settled;

  /// Completes when the mirror has the values of what its listeners ask
  /// for now: a read after it reads them, not null for not having them
  /// yet.
  Future<void> get settled => _settled ?? Future.value();

  @override
  Future<CallResult<Object?>> callAs(
    String command,
    Object? params,
    Shape<Object?> shape,
  ) => call(command, shape.toJson(params)! as Map<String, Object?>);

  @override
  Future<CallResult<Object?>> call(
    String command,
    Map<String, Object?> params,
  ) async {
    final client = this.client;
    if (client == null) return const CallFailed('not connected');
    await settled;
    final r = await client.callAt(command, params);
    if ((r.epoch, r.seq) case (final epoch?, final seq?)) {
      await mirror.reach(epoch, seq);
    }
    return r.result;
  }

  @override
  bool get synced => mirror.synced;

  @override
  WordStatus status(String word) => mirror.statusOf(word);

  @override
  Descriptor? descriptor(String word) => mirror.descriptorOf(word);

  @override
  Stream<WordStatus> statusChanges(String word) {
    late StreamController<WordStatus> out;
    StreamSubscription<void>? sub;
    WordStatus? last;
    void tell() {
      final now = mirror.statusOf(word);
      if (now == last) return;
      last = now;
      out.add(now);
    }

    out = StreamController<WordStatus>(
      onListen: () {
        tell();
        sub = mirror.statusChanges.listen((_) => tell());
      },
      onCancel: () => sub?.cancel(),
    );
    return out.stream;
  }
}
