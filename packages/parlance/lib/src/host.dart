import 'package:clock/clock.dart' show Clock;
import 'package:rpc_dart/rpc_dart.dart'
    show IRpcInterceptor, RpcClientConnection, RpcPeerEndpoint;

import 'participant/local.dart';
import 'participant/owner.dart' show IOwner;
import 'participant/participant.dart';
import 'registry/cause.dart';
import 'registry/registry.dart';
import 'registry/words.dart' show WordSet;
import 'remote/participant.dart';
import 'remote/session.dart';

/// How much a host keeps of what passed (SPEC §14): what it still answers
/// a retry, a feed catching up and `recent` from. The defaults suit an
/// app; a phone may keep less.
final class HostLimits {
  const HostLimits({
    this.dedupWindow = const Duration(minutes: 10),
    this.dedupLimit = 10000,
    this.retainTicks = 1000,
    this.retainBytes = 4 << 20,
    this.recentPerFact = 100,
    this.usersPerWord = 64,
  });

  /// A host that keeps nothing past what is now: no trail for `explain`,
  /// no `recent` facts, and a feed that fell behind takes a snapshot. What
  /// it does is the same; a retry of a call still gets its first answer.
  static const light = HostLimits(
    retainTicks: 0,
    retainBytes: 0,
    recentPerFact: 0,
  );

  /// How long, and how many, calls' answers are kept for a retry of the
  /// same id to get the first answer.
  final Duration dedupWindow;
  final int dedupLimit;

  /// How many ticks, and how many bytes of what is kept (ticks, call
  /// records, recent facts), whichever comes first; a feed behind them
  /// takes a snapshot.
  final int retainTicks;
  final int retainBytes;

  /// How many of each fact are kept for `recent`.
  final int recentPerFact;

  /// How many principals the uses of one word tell apart (SPEC §6.8);
  /// past them a use is counted under the principal's kind alone.
  final int usersPerWord;
}

/// What a host's `main` makes (SPEC §22): the registry of its process,
/// seen only as what `main` does with it. It makes the participants of the
/// app's parts (served across a connection, `serve`), says the old names of
/// words and the types the app adds, and ends it all.
///
/// Frozen (`app.dart`): what it shows is never taken away; only the
/// library makes one, so it may grow. The registry itself, for the
/// library's tools (a journal, an agent's session, an inspector), is
/// [registry], which promises nothing.
final class Host {
  Host({
    Clock? clock,
    LogScope? log,
    void Function(Object error, StackTrace stack)? onError,
    HostLimits limits = const HostLimits(),
  }) : registry = Registry(
         clock: clock,
         log: log,
         onError: onError,
         dedupWindow: limits.dedupWindow,
         dedupLimit: limits.dedupLimit,
         retainTicks: limits.retainTicks,
         retainBytes: limits.retainBytes,
         recentPerFact: limits.recentPerFact,
         usersPerWord: limits.usersPerWord,
       );

  /// The registry underneath, for the library's tools: not frozen, what it
  /// shows changes as the library does (`package:parlance/tools.dart`).
  final Registry registry;

  /// A participant of a part of the app, speaking as [who] (SPEC §22),
  /// its [owners] attached: each speaks as the part named by its
  /// vocabulary (`home@house`) and owns that vocabulary's words, none
  /// other's. It does what [rights] let it beyond, and its words name
  /// [access]'s readers and callers when they name none. One participant
  /// per principal: a second one of [who] is refused while the first
  /// lives.
  ///
  /// A participant served across a connection ([ServeAcross.serve]) has
  /// its owners at the other end: [vocabularies] grants the words they may
  /// own there, since the host does not see them.
  IParticipant participant(
    Principal who, {
    Iterable<IOwner> owners = const [],
    Iterable<WordSet> vocabularies = const [],
    ParticipantRights rights = ParticipantRights.none,
    WordAccess access = WordAccess.none,
  }) => registry.participant(
    who,
    owners: owners,
    vocabularies: vocabularies,
    rights: rights,
    access: access,
  );

  /// Says [old] is a name of the word [to] (SPEC §6.4): what asks by the
  /// old name gets the word, until the handle is disposed.
  IHandle alias(String old, String to) => registry.alias(old, to);

  /// Adds a type of values (SPEC §2) by [name]: [check] says why a value
  /// is not one, or null.
  IHandle registerType(String name, String? Function(Object? value) check) =>
      registry.registerType(name, check);

  /// Ends every participant and session, the last made first, and the
  /// registry.
  Future<void> dispose() => registry.dispose();

  /// Joins a host across [connection], from another process (SPEC §22.4):
  /// the participant the host serves there, the same as one in the host's
  /// process ([IRemoteParticipant]), rejoining after a drop. [onParticipantError] is
  /// told what the host refused, as [IRemoteParticipant.errors] is;
  /// [requires] names the protocol's features it cannot work without.
  static Future<IRemoteParticipant> join(
    RpcClientConnection connection, {
    void Function(ParticipantError error)? onParticipantError,
    LogScope? log,
    Set<String> requires = const {},
    Iterable<IRpcInterceptor> interceptors = const [],
  }) => RemoteParticipant.join(
    connection,
    onParticipantError: onParticipantError,
    log: log,
    requires: requires,
    interceptors: interceptors,
  );

  /// Joins a host across [endpoint], one its runtime hands it (a worker, a
  /// wasm module): it does not reconnect, and the endpoint stays its
  /// runtime's.
  static Future<IRemoteParticipant> joinEndpoint(
    RpcPeerEndpoint endpoint, {
    void Function(ParticipantError error)? onParticipantError,
    LogScope? log,
    Set<String> requires = const {},
  }) => RemoteParticipant.joinEndpoint(
    endpoint,
    onParticipantError: onParticipantError,
    log: log,
    requires: requires,
  );
}

/// A participant of a host served across a connection (SPEC §14, §22.4):
/// the part at the other end, which joins ([Host.join]), speaks as it, with
/// what it was given, and nothing more.
extension ServeAcross on IParticipant {
  /// Serves this participant across [endpoint]: the part there reads,
  /// calls and owns words as it; what it asks past [limits] is refused.
  /// The participant is the session's from then on, and goes with it. Only
  /// a new participant of a host is served, and once ([StateError]).
  IRemoteSession serve(
    RpcPeerEndpoint endpoint, {
    SessionLimits limits = const SessionLimits(),
    LogScope? log,
  }) => switch (this) {
    final LocalParticipant p => p.serve(endpoint, limits: limits, log: log),
    _ => throw StateError('$who is no participant of a host to serve'),
  };
}
