// Internal to the library: what these files show is not a promise
// Documented surface lives in schema.dart and app.dart.
// ignore_for_file: public_member_api_docs
import 'dart:async';

import 'package:rpc_dart/rpc_dart.dart' show RpcStatus, RpcStatusException;

import '../registry/descriptors.dart';
import '../registry/messages.dart';
import 'client.dart';

/// A remote participant's copy of the registry's states, kept by a feed and
/// resumed after a lost connection without gaps or repeats (SPEC §12).
final class RegistryMirror {
  String? _epoch;
  int _seq = 0;

  /// The epochs it followed before the one it follows now, the last few:
  /// what a call answered in one of them wrote it will never reach.
  final List<String> _past = [];

  /// Told when the session refused what it asked to carry, past its
  /// bound: the copy then has it carry everything, so nothing asked for
  /// goes missing (SPEC §12).
  void Function(Object error)? onRefused;

  /// The session's subscription the copy follows, and what it asked for.
  int _subscription = 0;
  ({Set<String>? states, Set<String>? facts})? _wanted;
  Map<String, Object?> _catalog = const {};
  final Map<String, Map<String?, Object?>> _states = {};
  ParlanceClient? _client;
  StreamSubscription<RemoteFeed>? _sub;
  bool _synced = false;
  final StreamController<Tick> _ticks = StreamController.broadcast();
  final StreamController<void> _changes = StreamController.broadcast();
  final StreamController<void> _catalogChanges = StreamController.broadcast();
  final StreamController<void> _statusChanges = StreamController.broadcast();

  /// From the catalog: each word's kind by name, the words the session's
  /// principal may not read or call, the commands that cannot run now.
  Map<String, String> _words = const {};
  Set<String> _closed = const {};
  Map<String, String> _unavailable = const {};

  String? get epoch => _epoch;
  int get seq => _seq;

  /// The catalog as the session's principal sees it (`describeFor`).
  Map<String, Object?> get catalog => _catalog;

  /// Whether the session's principal can use the word [name] now (SPEC
  /// §6.5), as the catalog and the availability the feed brought last say.
  WordStatus statusOf(String name) {
    final n = canonical(name);
    final kind = _words[n];
    if (kind == null) return const WordMissing();
    if (_closed.contains(n)) return const WordNotPermitted();
    if (kind == 'command' || kind == 'query') {
      if (_unavailable[n] case final why?) return WordUnavailable(why);
    }
    return const WordReady();
  }

  /// The catalog came, or a command came to run or stopped: a word's
  /// [statusOf] may have changed.
  Stream<void> get statusChanges => _statusChanges.stream;

  /// Whether the copy follows the registry now.
  bool get synced => _synced;

  /// The ticks applied, in order.
  Stream<Tick> get ticks => _ticks.stream;

  /// Something changed: a snapshot, a tick, the catalog, the connection.
  Stream<void> get changes => _changes.stream;

  /// The catalog came: first after following, and on every change of it
  /// (descriptors or entities).
  Stream<void> get catalogChanges => _catalogChanges.stream;

  Object? read(String state, {String? key}) => _states[canonical(state)]?[key];

  /// The name [name] stands for, as the catalog's `aliases` say.
  String canonical(String name) => switch (_catalog['aliases']) {
    final Map<Object?, Object?> a when a[name] is String => a[name]! as String,
    _ => name,
  };

  /// Completes when the copy has the seq [seq] of [epoch] (what a call
  /// answered at it wrote), however long its feed takes: the host tells a
  /// seq a call or `describe` answered at even when nothing of it is
  /// carried. Answers whether it got there: not when the copy lost the
  /// registry (`synced` false, as a reader sees), the registry started
  /// again, or after [timeout] when one is given.
  Future<bool> reach(String epoch, int seq, {Duration? timeout}) async {
    bool there() => _synced && _epoch == epoch && _seq >= seq;
    // Of a run the registry left (it started again): never reached.
    bool gone() => _past.contains(epoch);
    if (there()) return true;
    if (gone() || !_synced) return false;
    try {
      final reached = changes.firstWhere((_) => there() || gone() || !_synced);
      await (timeout == null ? reached : reached.timeout(timeout));
      return there();
    } on TimeoutException {
      return false;
    } on StateError {
      return false;
    }
  }

  Map<String?, Object?> readAll(String state) =>
      Map.unmodifiable(_states[canonical(state)] ?? const {});

  /// The states the copy keeps, and the facts its ticks carry; null for
  /// all.
  Set<String>? get states => _wanted?.states;
  Set<String>? get facts => _wanted?.facts;

  /// Keeps only [states] and hears only [facts] (null: all of them);
  /// completes when the copy has the values of the states it keeps now,
  /// however long its feed takes, or once it lost the registry (`synced`
  /// false). Kept over a new connection ([follow]).
  Future<void> subscribe({Set<String>? states, Set<String>? facts}) async {
    final client = _client;
    if (client == null) {
      _wanted = (states: states, facts: facts);
      return;
    }
    int n;
    try {
      n = await client.subscribe(states: states, facts: facts);
      _wanted = (states: states, facts: facts);
    } on RpcStatusException catch (e) {
      if (e.statusCode != RpcStatus.resourceExhausted) rethrow;
      // Past the session's bound: rather than the states it asked for
      // and was not given never coming, everything comes, as to a
      // session that never subscribed.
      onRefused?.call(e);
      _wanted = null;
      n = await client.subscribe();
    }
    if (_subscription >= n || _client != client || !_synced) return;
    try {
      await changes.firstWhere(
        (_) => _subscription >= n || _client != client || !_synced,
      );
    } on StateError {
      return;
    }
  }

  /// Follows [client]'s feed, resuming after what the copy already has.
  /// Call again with a new client after the connection was lost.
  void follow(ParlanceClient client) {
    _client = client;
    _subscription = 0;
    if (_wanted case (:final states, :final facts)) {
      // A new session carries everything until it subscribes: before the
      // feed, so its snapshot has only what the copy keeps.
      unawaited(
        client
            .subscribe(states: states, facts: facts)
            .then((_) {}, onError: (Object _) {}),
      );
    }
    _malformed.clear();
    _feed(client);
  }

  /// Follows [client]'s feed, after what the copy has.
  void _feed(ParlanceClient client) {
    unawaited(_sub?.cancel());
    _sub = client
        .feed(epoch: _epoch, since: _epoch == null ? null : _seq)
        .listen(
          _apply,
          onError: (Object _) => _lost(),
          onDone: _lost,
          cancelOnError: true,
        );
  }

  void _lost() {
    _synced = false;
    _changes.add(null);
  }

  /// The descriptors the catalog told, made of its JSON when asked.
  Map<String, Object?> _descriptorJson = const {};
  final Map<String, Descriptor> _descriptors = {};

  /// The word named [name] as the catalog last told it; null when it told
  /// none, or a word of a kind a newer parlance has and this one does not
  /// (SPEC §14).
  Descriptor? descriptorOf(String name) {
    final n = canonical(name);
    if (_descriptors[n] case final d?) return d;
    final json = _descriptorJson[n];
    if (json == null) return null;
    try {
      return _descriptors[n] = Descriptor.fromJson(json);
    } on FormatException {
      return null;
    }
  }

  /// Takes [json], the catalog as the session's principal sees it
  /// (`describe` answers it too), as the one it has now. One it cannot
  /// read is a [FormatException], and the copy keeps the one it had.
  void takeCatalog(Map<String, Object?> json) {
    final Map<String, Object?> descriptors;
    final Map<String, String> words;
    final Set<String> closed;
    final Map<String, String> unavailable;
    try {
      final all = [
        for (final d in json['descriptors'] as List? ?? const [])
          (d as Map).cast<String, Object?>(),
      ];
      descriptors = {for (final d in all) d['name']! as String: d};
      words = {for (final d in all) d['name']! as String: d['is']! as String};
      closed = {
        for (final u in json['unreadable'] as List? ?? const []) u as String,
        for (final e in (json['access'] as Map? ?? const {}).entries)
          if (e.value == Access.deny.name) e.key as String,
      };
      unavailable = Map<String, String>.from(
        json['unavailable'] as Map? ?? const {},
      );
      for (final k in json['kinds'] as List? ?? const []) {
        (k as Map)['name']! as String;
      }
      if (json['aliases'] case final a?) Map<String, String>.from(a as Map);
    } on Object catch (e) {
      throw FormatException('a catalog this side cannot read: $e');
    }
    _catalog = json;
    _descriptorJson = descriptors;
    _descriptors.clear();
    _words = words;
    _closed = closed;
    _unavailable = unavailable;
    // The values of a state that left the catalog go with it, though no
    // tick removed them.
    _states.removeWhere((name, _) => _words[name] != 'state');
    _catalogChanges.add(null);
    _statusChanges.add(null);
  }

  /// Told when the feed brought what this side cannot read (a host's
  /// defect): the copy follows again from a snapshot, [gaveUp] when that
  /// came more than [malformedLimit] times within a minute and it stopped
  /// following.
  void Function(Object error, {required bool gaveUp})? onMalformed;

  /// Told when the host ended the session, the connection still up
  /// ([RemoteEnded]): its feed ends after.
  void Function(String why)? onEnded;

  /// Told when a snapshot says facts went by that its ticks never brought
  /// (`factsLost`): it was away or behind past what the host retains.
  void Function()? onFactsLost;

  /// How many times within a minute the copy follows again over what it
  /// could not read before it stops: a host that sends it every time is
  /// not asked for ever.
  static const malformedLimit = 3;
  final List<DateTime> _malformed = [];

  void _unreadable(Object error) {
    final now = DateTime.now();
    _malformed
      ..removeWhere((t) => now.difference(t) > const Duration(minutes: 1))
      ..add(now);
    final gaveUp = _malformed.length > malformedLimit;
    onMalformed?.call(error, gaveUp: gaveUp);
    if (gaveUp) {
      unawaited(_sub?.cancel());
      _sub = null;
      _lost();
      return;
    }
    _epoch = null;
    if (_client case final c?) _feed(c);
  }

  void _apply(RemoteFeed item) {
    try {
      _take(item);
    } on Object catch (e) {
      _unreadable(e);
    }
  }

  void _take(RemoteFeed item) {
    switch (item) {
      case RemoteMalformed(:final kind, :final error):
        return _unreadable(
          FormatException('a $kind item this side cannot read: $error'),
        );
      case RemoteCatalog(:final json):
        takeCatalog(json);
        // A feed resumed in the same epoch carries on from the copy's seq:
        // the copy follows again from its first item, though nothing may
        // have happened since to send.
        if (_epoch != null && json['epoch'] == _epoch) _synced = true;
      case RemoteChoices(:final name, :final json):
        // The choices of one name, in their place among the rest (the
        // catalog's `kinds`); the rest of the catalog stays as it was.
        final choices = [
          for (final c in _catalog['kinds'] as List? ?? const [])
            if ((c as Map)['name'] != name) c else ?json,
        ];
        if (json != null && !choices.contains(json)) choices.add(json);
        _catalog = {..._catalog, 'kinds': choices};
        _catalogChanges.add(null);
      case RemoteSnapshot(:final snapshot, :final subscription):
        _subscription = subscription;
        if (_epoch case final was? when was != snapshot.epoch) {
          _past.add(was);
          if (_past.length > 8) _past.removeAt(0);
        }
        _epoch = snapshot.epoch;
        _seq = snapshot.seq;
        _states
          ..clear()
          ..addAll({
            for (final e in snapshot.states.entries) e.key: {...e.value},
          });
        _synced = true;
        if (snapshot.factsLost) onFactsLost?.call();
      case RemoteTick(:final tick):
        if (tick.epoch != _epoch || tick.from != _seq + 1) {
          // A gap: start over from a snapshot.
          _epoch = null;
          if (_client case final c?) follow(c);
          return;
        }
        for (final c in tick.changes) {
          if (c.removed) {
            _states[c.state]?.remove(c.key);
          } else {
            (_states[c.state] ??= {})[c.key] = c.value;
          }
        }
        _seq = tick.to;
        _synced = true;
        _ticks.add(tick);
      case RemoteEnded(:final why):
        onEnded?.call(why);
        return;
      case RemoteUnavailable(:final unavailable):
        _unavailable = unavailable;
        _statusChanges.add(null);
        return;
      case RemoteValues(:final subscription, :final states, :final keep):
        _subscription = subscription;
        if (keep != null) _states.removeWhere((k, _) => !keep.contains(k));
        for (final e in states.entries) {
          _states[e.key] = {...e.value};
        }
    }
    _changes.add(null);
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    await _ticks.close();
    await _changes.close();
    await _catalogChanges.close();
    await _statusChanges.close();
  }
}
