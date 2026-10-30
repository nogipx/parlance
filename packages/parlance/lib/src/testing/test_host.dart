import 'dart:async';

import 'package:clock/clock.dart';
import 'package:rpc_dart/rpc_dart.dart';

import '../participant/local.dart';
import '../participant/owner.dart' show IOwner;
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
/// stood in for by [stateOf], [commandOf], [factOf]; what it did is read
/// back by [written], [said] and [calls] after [settle].
final class TestHost {
  factory TestHost({Clock? clock, LogScope? log}) {
    final errors = <Object>[];
    return TestHost._(
      Host(clock: clock, log: log, onError: (e, _) => errors.add(e)),
      errors,
    );
  }

  TestHost._(this.host, this.errors) {
    _ticks = registry.ticks.listen(ticks.add);
    _calls = registry.calls.listen(calls.add);
  }

  /// The host the test runs, as `main` would make it.
  final Host host;

  /// Its registry, for what the test reads back.
  Registry get registry => host.registry;

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
  }) => host.participant(
    who,
    owners: owners,
    vocabularies: vocabularies,
    rights: rights,
    access: access,
  );

  /// The module under test across a connection, in memory: the host
  /// serves it a participant made as [participant] makes one, and it
  /// joins. The connection carries frames as bytes, encoded and decoded as
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
    final session = participant(
      who,
      vocabularies: vocabularies,
      rights: rights,
      access: access,
    ).serve(host);
    host.start();
    _sessions.add(session);
    _hosts.add(host);
    final connection = RpcClientConnection(
      transportFactory: (_) async => client,
      shouldReconnect: (_) => false,
    );
    _connections.add(connection);
    final p = await Host.join(connection);
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

  /// A stand-in owner of another module's state [word], holding [value];
  /// write it again through what it answers.
  IStateWriterOf<T> stateOf<T>(IStateWord<T> word, T value, {String? key}) {
    final writer = _standInFor(word.name).state(word).define();
    writer.set(value, key: key);
    return writer;
  }

  /// A stand-in serving another module's command [word]: every call's
  /// params are kept in [Stub.params]; it answers what [answer] gives, or
  /// nothing. Anyone may call it, unless [callers] say otherwise.
  Stub<P, R> commandOf<P, R>(
    ICommandWord<P, R> word, {
    FutureOr<R> Function(P params)? answer,
    Callers callers = const Callers({'*': Access.allow}),
  }) {
    final stub = Stub<P, R>._();
    _standInFor(word.name).command(word).define((call) {
      stub.params.add(call.params);
      if (answer != null) return answer(call.params);
      return null as R;
    }, callers: callers);
    return stub;
  }

  /// A stand-in speaker of another module's fact [word].
  IFactEmitterOf<T> factOf<T>(IFactWord<T> word) =>
      _standInFor(word.name).fact(word).define();

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

  /// The finished calls of [word], in order. Read after [settle].
  List<CallRecord> callsOf(String word) => [
    for (final c in calls)
      if (c.command == registry.canonical(word)) c,
  ];

  /// Lets what is under way come: ticks and call records delivered,
  /// participants across a connection answered.
  Future<void> settle() async {
    for (final p in _remotes) {
      await p.settle();
    }
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// Ends it all: the participants across a connection, their sessions,
  /// the stand-ins and the registry.
  Future<void> dispose() async {
    for (final p in _remotes) {
      await (p as RemoteParticipant).close();
    }
    for (final c in _connections) {
      await c.dispose();
    }
    for (final s in _sessions) {
      s.close();
    }
    for (final h in _hosts) {
      await h.close();
    }
    for (final p in _standIns.values) {
      p.dispose();
    }
    await _ticks.cancel();
    await _calls.cancel();
    await host.dispose();
  }
}

/// A stand-in for another module's command ([TestHost.commandOf]).
final class Stub<P, R> {
  Stub._();

  /// The params of every call it served, in order.
  final List<P> params = [];
}
