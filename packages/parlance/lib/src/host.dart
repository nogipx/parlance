import 'package:clock/clock.dart' show Clock;
import 'package:rpc_dart/rpc_dart.dart'
    show IRpcInterceptor, RpcClientConnection, RpcPeerEndpoint;

import 'participant/local.dart';
import 'participant/participant.dart';
import 'registry/cause.dart';
import 'registry/registry.dart';
import 'registry/words.dart' show WordSet;
import 'remote/participant.dart';
import 'remote/session.dart';

/// How much a host keeps of what passed (SPEC §14): what it still answers
/// a retry, a feed catching up and `recent` from. The defaults suit an
/// app; a phone may keep less.
final class HostBounds {
  const HostBounds({
    this.dedupWindow = const Duration(minutes: 10),
    this.dedupLimit = 10000,
    this.retainTicks = 1000,
    this.retainBytes = 4 << 20,
    this.recentPerFact = 100,
    this.usersPerWord = 64,
  });

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
/// app's parts, serves guests across connections, says the old names of
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
    Set<String> overriders = const {},
    HostBounds bounds = const HostBounds(),
  }) : registry = Registry(
         clock: clock,
         log: log,
         onError: onError,
         overriders: overriders,
         dedupWindow: bounds.dedupWindow,
         dedupLimit: bounds.dedupLimit,
         retainTicks: bounds.retainTicks,
         retainBytes: bounds.retainBytes,
         recentPerFact: bounds.recentPerFact,
         usersPerWord: bounds.usersPerWord,
       );

  /// The registry underneath, for the library's tools: not frozen, what it
  /// shows changes as the library does (`package:parlance/registry.dart`).
  final Registry registry;

  /// A participant of a part of the app, speaking as [who] (SPEC §22):
  /// it defines words only in [vocabularies], does what [rights] let it
  /// beyond, and its words name [access]'s readers and callers when they
  /// name none. One participant per principal: a second one of [who] is
  /// refused while the first lives.
  IParticipant participant(
    Principal who, {
    Iterable<WordSet> vocabularies = const [],
    ParticipantRights rights = ParticipantRights.none,
    WordAccess access = WordAccess.none,
  }) => registry.participant(
    who,
    vocabularies: vocabularies,
    rights: rights,
    access: access,
  );

  /// Serves a guest across [endpoint] (SPEC §14, §22.4) as [who], with
  /// what [participant] would give it: what it asks past [limits] is
  /// refused. A new session of [who] takes the place of one there.
  IGuestSession serve(
    RpcPeerEndpoint endpoint,
    Principal who, {
    Iterable<WordSet> vocabularies = const [],
    ParticipantRights rights = ParticipantRights.none,
    WordAccess access = WordAccess.none,
    SessionLimits limits = const SessionLimits(),
    LogScope? log,
  }) => registry
      .participant(
        who,
        vocabularies: vocabularies,
        rights: rights,
        access: access,
      )
      .serve(endpoint, limits: limits, log: log);

  /// Says [old] is a name of the word [now] (SPEC §6.4): what asks by the
  /// old name gets the word, until the handle is disposed.
  IHandle alias(String old, String now) => registry.alias(old, now);

  /// Adds a type of values (SPEC §2) by [name]: [check] says why a value
  /// is not one, or null.
  IHandle registerType(String name, String? Function(Object? value) check) =>
      registry.registerType(name, check);

  /// Ends every participant and session, the last made first, and the
  /// registry.
  Future<void> dispose() => registry.dispose();
}

/// How a guest's `main` joins its host (SPEC §22.4): the participant it
/// gets is the same as one in the host's process ([IGuest]).
abstract final class Guest {
  /// Joins across [connection], rejoining after a drop; [onError] is told
  /// what the host refused, as [IGuest.errors] is. [requires] names the
  /// protocol's features it cannot work without.
  static Future<IGuest> join(
    RpcClientConnection connection, {
    void Function(ParticipantError error)? onError,
    LogScope? log,
    Set<String> requires = const {},
    Iterable<IRpcInterceptor> interceptors = const [],
  }) => RemoteParticipant.join(
    connection,
    onError: onError,
    log: log,
    requires: requires,
    interceptors: interceptors,
  );

  /// Joins across [endpoint], one its runtime hands it (a worker, a wasm
  /// guest): it does not reconnect, and the endpoint stays its runtime's.
  static Future<IGuest> over(
    RpcPeerEndpoint endpoint, {
    void Function(ParticipantError error)? onError,
    LogScope? log,
    Set<String> requires = const {},
  }) => RemoteParticipant.over(
    endpoint,
    onError: onError,
    log: log,
    requires: requires,
  );
}
