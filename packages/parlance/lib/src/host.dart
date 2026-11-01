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

/// What a host's `main` makes (SPEC §22): the registry of its process,
/// seen only as what `main` does with it. It makes the participants of the
/// app's parts in this process ([participant]) and serves those across a
/// connection ([serve]), says the old names of words, and ends it all.
///
/// Frozen (`app.dart`): what it shows is never taken away; only the
/// library makes one, so it may grow. The registry itself, for the
/// library's tools (a journal, an agent's session, an inspector), is
/// `host.registry` in `package:parlance/tools.dart`, which promises
/// nothing.
final class Host {
  /// One registry of its own; [clock], [log] and [onError] are its
  /// registry's, [limits] how much it keeps.
  Host({
    Clock? clock,
    LogScope? log,
    void Function(Object error, StackTrace stack)? onError,
    HostLimits limits = const HostLimits(),
  }) : _registry = Registry(
         clock: clock,
         log: log,
         onError: onError,
         limits: limits,
       );

  final Registry _registry;

  /// A participant of a part of the app in this process, speaking as
  /// [who] (SPEC §22), its [owners] attached: each speaks as [who] of that
  /// owner, named by its vocabulary (`home@house`), and owns that
  /// vocabulary's words, none other's. [vocabularies] grants more, whose
  /// words come at run time (`WordSet.open`). It does what [rights] let it
  /// beyond, and its words name [access]'s readers and callers when they
  /// name none.
  ///
  /// A vocabulary is one participant's: one another live participant has
  /// is refused ([NotPermitted]), unless that one is a session of [who]
  /// whose connection went unseen ([serve]): it ends, and this one takes
  /// its place. Several participants may speak as one principal, each in
  /// vocabularies of its own.
  IParticipant participant(
    Principal who, {
    Iterable<IOwner> owners = const [],
    Iterable<WordSet> vocabularies = const [],
    ParticipantRights rights = ParticipantRights.none,
    WordAccess access = WordAccess.none,
  }) => _registry.participant(
    who,
    owners: owners,
    vocabularies: vocabularies,
    rights: rights,
    access: access,
  );

  /// Serves a participant speaking as [who] to the part at the other end
  /// of [endpoint], which joins ([join], [joinEndpoint]) (SPEC §14, §22.4):
  /// it reads, calls and owns words as [who], and nothing more. Its owners
  /// are at the other end, where the host does not see them: [vocabularies]
  /// grants the words they may own. [rights] and [access] are as
  /// [participant]'s; what it asks past [limits] is refused.
  ///
  /// The session ends when its connection goes, by its `dispose` (the part
  /// across is told, and does not join again), or with the host. A session
  /// of [who] in one of [vocabularies] whose connection went unseen (a
  /// link half open) ends, and this one takes its place, as an MQTT broker
  /// takes a client's over. One endpoint serves one session.
  IRemoteSession serve(
    Principal who,
    RpcPeerEndpoint endpoint, {
    Iterable<WordSet> vocabularies = const [],
    ParticipantRights rights = ParticipantRights.none,
    WordAccess access = WordAccess.none,
    SessionLimits limits = const SessionLimits(),
    LogScope? log,
  }) {
    final p = _registry.participant(
      who,
      vocabularies: vocabularies,
      rights: rights,
      access: access,
    );
    try {
      return p.serve(endpoint, limits: limits, log: log);
    } on Object {
      p.dispose();
      rethrow;
    }
  }

  /// Says [old] is a name of the word [to] (SPEC §6.4): what asks by the
  /// old name gets the word, until the handle is disposed.
  IHandle alias(String old, String to) => _registry.alias(old, to);

  /// Ends every participant and session, the last made first, and the
  /// registry. The parts across are not told: their connections go with
  /// the host, and they join the next one.
  Future<void> dispose() => _registry.dispose();

  /// Joins a host across [connection], from another process (SPEC §22.4):
  /// the participant the host serves there, the same as one in the host's
  /// process ([IRemoteParticipant]), rejoining after a drop. [onParticipantError] is
  /// told what the host refused, as [IRemoteParticipant.errors] is;
  /// [requires] names the protocol's features it cannot work without.
  /// [HostUnreachable] when the host gives it no view of the registry.
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

/// The registry underneath a [Host], for the library's tools: not frozen,
/// what it shows changes as the library does.
extension HostRegistry on Host {
  /// The registry underneath: for tools, not frozen.
  Registry get registry => _registry;
}
