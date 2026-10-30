import 'dart:async';

import 'package:clock/clock.dart';
import 'package:rpc_dart/rpc_dart.dart';

import '../participant/local.dart';
import '../participant/owner.dart' show IOwner, OwnerGroup;
import '../participant/participant.dart';
import '../registry/cause.dart';
import '../registry/descriptors.dart';
import '../registry/messages.dart';
import '../registry/registry.dart';
import '../registry/words.dart';
import '../remote/participant.dart';
import '../remote/session.dart';
import '../host.dart';

/// A registry for a test, what happened in it, and stand-ins for the
/// modules the test leaves out (SPEC §24).
///
/// The module under test gets a participant of its own ([participant], or
/// [join] for one across a connection); the words of others it needs are
/// stood in for by [standInState], [standInKeyed], [standInCommand],
/// [standInFact]; what it did is read
/// back by [written], [said] and [calls] after [settle].
final class TestHost {
  factory TestHost({Clock? clock, LogScope? log}) {
    final errors = <Object>[];
    return TestHost._(
      Host(clock: clock, log: log, onError: (e, _) => errors.add(e)),
      errors,
    );
  }

  TestHost._(this._host, this.errors) {
    _ticks = registry.ticks.listen(ticks.add);
    _calls = registry.calls.listen(calls.add);
  }

  /// The host the test runs, as `main` would make it.
  final Host _host;

  /// Its registry, for what the test reads back.
  Registry get registry => _host.registry;

  /// Every tick committed, in order, once [settle] has let them come.
  final List<Tick> ticks = [];

  /// Every finished call, in order, once [settle] has let them come.
  final List<CallRecord> calls = [];

  /// What went to the registry's error sink: a guard that threw, a
  /// listener that failed. A test that expects none says
  /// `expect(host.errors, isEmpty)`.
  final List<Object> errors;

  late final StreamSubscription<Tick> _ticks;
  late final StreamSubscription<CallRecord> _calls;
  final Map<String, LocalParticipant> _standIns = {};
  final List<IParticipant> _modules = [];
  final List<IRemoteSession> _sessions = [];
  final List<RpcPeerEndpoint> _hosts = [];
  final List<IRemoteParticipant> _remotes = [];
  final List<RpcClientConnection> _connections = [];

  /// A participant for the module under test, its [owners] attached, as
  /// `main` would make it.
  IParticipant participant(
    Principal who, {
    Iterable<IOwner> owners = const [],
    Iterable<WordSet> vocabularies = const [],
    ParticipantRights rights = ParticipantRights.none,
    WordAccess access = WordAccess.none,
  }) {
    final p = _host.participant(
      who,
      owners: owners,
      vocabularies: vocabularies,
      rights: rights,
      access: access,
    );
    _modules.add(p);
    return p;
  }

  /// The module under test across a connection, in memory: the host
  /// serves it ([Host.serve]), and it joins. The connection carries frames as bytes, encoded and decoded as
  /// across a process boundary, so what passes here passes over a real
  /// wire: a value that is no JSON fails here as it would there.
  Future<IRemoteParticipant> join(
    Principal who, {
    Iterable<WordSet> vocabularies = const [],
    ParticipantRights rights = ParticipantRights.none,
    WordAccess access = WordAccess.none,
  }) async {
    final (client, server) = RpcChannelTransport.pair();
    final host = RpcPeerEndpoint(transport: server);
    final session = _host.serve(
      who,
      host,
      vocabularies: vocabularies,
      rights: rights,
      access: access,
    );
    host.start();
    _sessions.add(session);
    _hosts.add(host);
    final connection = RpcClientConnection(
      transportFactory: (_) async => client,
      shouldReconnect: (_) => false,
    );
    _connections.add(connection);
    // Its owners read the time by the host's clock, a test's when given.
    final p = await RemoteParticipant.join(connection, clock: registry.clock);
    _remotes.add(p);
    return p;
  }

  /// The participant standing in for the owner of [name]: the owner of
  /// its vocabulary (`water` of `water.level`), another module's than the
  /// one under test.
  LocalParticipant _standInFor(String name) {
    final vocabulary = name.split('.').first;
    return _standIns[vocabulary] ??= registry.participant(
      Principal('stand-in', vocabulary),
      vocabularies: [WordSet.open(vocabulary)],
    );
  }

  /// A stand-in owner of another module's state [word], one with no key,
  /// holding [value]: a [Single], as an owner keeps its own, set and
  /// removed again by the test.
  Single<T> standInState<T>(IStateWord<T> word, T value) {
    if (word.key != null) {
      throw ArgumentError('${word.name} is keyed: standInKeyed it');
    }
    final s = Single<T>()..set(value);
    Single.attach(
      s,
      GeneratedWords(_standInFor(word.name)).state(word).define(),
    );
    Single.write(s);
    return s;
  }

  /// A stand-in owner of another module's keyed state [word], holding
  /// [values] by key: a [Keyed], as an owner keeps its own, set and
  /// removed again by the test.
  Keyed<T> standInKeyed<T>(IStateWord<T> word, Map<String, T> values) {
    if (word.key == null) {
      throw ArgumentError('${word.name} has no key: standInState it');
    }
    final k = Keyed<T>();
    for (final MapEntry(:key, :value) in values.entries) {
      k.set(key, value);
    }
    Keyed.attach(
      k,
      GeneratedWords(_standInFor(word.name)).state(word).define(),
    );
    Keyed.writeAll(k);
    return k;
  }

  /// A stand-in serving another module's command [word]: every call's
  /// params are kept in [CommandStandIn.params]; it answers what [answer]
  /// gives, or nothing, when [word] may answer nothing ([ArgumentError]
  /// otherwise). Anyone may call it, unless [callers] say otherwise.
  CommandStandIn<P, R> standInCommand<P, R>(
    ICommandWord<P, R> word, {
    FutureOr<R> Function(P params)? answer,
    Callers callers = Callers.anyone,
  }) {
    if (answer == null && null is! R) {
      throw ArgumentError(
        '${word.name} answers $R, never nothing: give answer',
      );
    }
    final stub = CommandStandIn<P, R>._();
    GeneratedWords(_standInFor(word.name)).command(word).serve((params) {
      stub.params.add(params);
      if (answer != null) return answer(params);
      return null as R;
    }, callers: callers);
    return stub;
  }

  /// A stand-in giver of the choices of [name], as another module's owner
  /// gives them (`choices(name:, list:)`): what a `@ChoiceOf(name)` and a
  /// state keyed by [name] are held to. [ChoicesStandIn.set] changes them.
  ChoicesStandIn standInChoices(String name, Iterable<Choice> choices) {
    final stub = ChoicesStandIn._([...choices]);
    final p = _standInFor('$name.choices');
    p.addChoices(Choices(name, list: () => [...stub._now]));
    stub._changed = () => p.choicesChanged(name);
    return stub;
  }

  /// A stand-in speaker of another module's fact [word].
  IFactSayerOf<T> standInFact<T>(IFactWord<T> word) =>
      GeneratedWords(_standInFor(word.name)).fact(word).define();

  /// The values [word] (of [key]) was given, in order, as committed: null
  /// for a removal. Read after [settle].
  List<T?> written<T>(IStateWord<T> word, {String? key}) => [
    for (final t in ticks)
      for (final c in t.changes)
        if (c.state == registry.canonical(word.name) && c.key == key)
          c.removed ? null : word.shape.fromJson(c.value),
  ];

  /// The payloads of [word] said, in order. Read after [settle].
  List<T> said<T>(IFactWord<T> word) => [
    for (final t in ticks)
      for (final f in t.facts)
        if (f.fact == registry.canonical(word.name))
          word.shape.fromJson(f.payload),
  ];

  /// The finished calls of [word], a command or a query, in order. Read
  /// after [settle].
  List<CallRecord> callsOf(IWord word) => [
    for (final c in calls)
      if (c.command == registry.canonical(word.name)) c,
  ];

  /// Lets what is under way come: participants across a connection
  /// answered, owners done, ticks and call records delivered, until 20
  /// turns of the event loop in a row bring nothing new. What waits on
  /// time (a timer, a clock) is not waited for.
  Future<void> settle() async {
    for (final p in _remotes) {
      await p.settle();
    }
    var quiet = 0;
    for (var i = 0; i < 1000 && quiet < 20; i++) {
      final before = ticks.length + calls.length;
      await OwnerGroup.idle();
      quiet = ticks.length + calls.length == before ? quiet + 1 : 0;
    }
  }

  /// Ends it all: the participants across a connection, their sessions,
  /// the modules' participants, the last made first, then the stand-ins,
  /// so a module never sees what it reads go before it does, and the
  /// registry.
  Future<void> dispose() async {
    for (final p in _remotes) {
      await p.dispose();
    }
    for (final c in _connections) {
      await c.dispose();
    }
    for (final s in _sessions) {
      s.dispose();
    }
    for (final h in _hosts) {
      await h.close();
    }
    for (final p in _modules.reversed) {
      p.dispose();
    }
    for (final p in _standIns.values) {
      p.dispose();
    }
    await _ticks.cancel();
    await _calls.cancel();
    await _host.dispose();
  }
}

/// A stand-in for another module's choices ([TestHost.standInChoices]).
final class ChoicesStandIn {
  ChoicesStandIn._(this._now);

  List<Choice> _now;
  void Function()? _changed;

  /// The choices there are now.
  List<Choice> get choices => List.unmodifiable(_now);

  /// Makes [choices] the ones there are: who asks is told.
  void set(Iterable<Choice> choices) {
    _now = [...choices];
    _changed?.call();
  }
}

/// A stand-in for another module's command ([TestHost.standInCommand]).
final class CommandStandIn<P, R> {
  CommandStandIn._();

  /// The params of every call it served, in order.
  final List<P> params = [];
}
