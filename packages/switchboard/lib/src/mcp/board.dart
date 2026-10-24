import '../registry/cause.dart';
import '../registry/messages.dart';
import '../registry/registry.dart';

/// What the MCP tools need of a registry, whether it is in this process or
/// reached over remote: the same words, read and called on behalf of one
/// principal.
abstract interface class Board {
  /// The catalog as its principal sees it (Registry.describeFor).
  Future<Map<String, Object?>> describe();

  /// Every value of [state], by key (null for an unkeyed state); throws
  /// [BoardOffline] when the registry cannot be reached, and [BoardBehind]
  /// when what it holds is older than the board's last call.
  Future<Map<String?, Object?>> readAll(String state);

  /// Calls [command]; a read after it reads what it wrote. When the answer
  /// is lost on the way, [CallLost] with the id to retry with.
  Future<CallResult<Object?>> call(
    String command,
    Map<String, Object?> params, {
    String? id,
  });

  /// The last [n] facts of [fact], oldest first.
  Future<List<FactMessage>> recentFacts(String fact, int n);

  /// Why [state] (of [key]) is as it is (Registry.explain).
  Future<Explanation> why(String state, {String? key});

  /// Every layer there is.
  Future<List<LayerInfo>> layers();

  /// The catalog changed: the tools may be others.
  Stream<void> get catalogChanges;
}

/// The registry cannot be reached now: what the board last had is not
/// told as if it were now.
final class BoardOffline implements Exception {
  const BoardOffline(this.seq);

  /// The last seq the board had.
  final int seq;

  @override
  String toString() =>
      'the registry is not reachable now (last seen at seq $seq)';
}

/// The board's copy has not caught up with the board's last call: what
/// it would read may be older than that call's effect.
final class BoardBehind implements Exception {
  const BoardBehind(this.seq, this.needed);

  /// The seq the copy has, and the one the last call answered at.
  final int seq;
  final int needed;

  @override
  String toString() =>
      'the copy is behind your last call (at seq $seq, needs $needed); '
      'try again in a moment';
}

/// A board on a registry in this process.
final class LocalBoard implements Board {
  LocalBoard(this.registry, {required this.by});

  final Registry registry;

  /// On whose behalf the agent acts.
  final Principal by;

  @override
  Future<Map<String, Object?>> describe() async => registry.describeFor(by);

  void _mayRead(String state) {
    if (!registry.mayRead(by, state)) {
      throw StateError('${by.selector} may not read $state');
    }
  }

  @override
  Future<Map<String?, Object?>> readAll(String state) async {
    _mayRead(state);
    return registry.readAll(state);
  }

  @override
  Future<CallResult<Object?>> call(
    String command,
    Map<String, Object?> params, {
    String? id,
  }) => registry.call(command, params, by: by, id: id);

  @override
  Future<List<FactMessage>> recentFacts(String fact, int n) async =>
      registry.recent(fact, n);

  @override
  Future<Explanation> why(String state, {String? key}) async {
    _mayRead(state);
    return registry.explain(state, key: key);
  }

  @override
  Future<List<LayerInfo>> layers() async => [
    for (final l in registry.layers())
      if (registry.mayRead(by, l.state)) l,
  ];

  @override
  Stream<void> get catalogChanges => registry.catalogChanges;
}
