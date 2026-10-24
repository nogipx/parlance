import '../registry/cause.dart';
import '../registry/descriptors.dart';
import '../registry/messages.dart';
import '../registry/registry.dart';

/// What the MCP tools need of a registry, whether it is in this process or
/// reached over remote: the same words, read and called on behalf of one
/// principal.
abstract interface class Board {
  /// The catalog as `describe` gives it, with `access` (what this board's
  /// principal may call) and `unavailable` (commands that cannot run now,
  /// and why).
  Future<Map<String, Object?>> describe();

  /// Every value of [state], by key (null for an unkeyed state).
  Future<Map<String?, Object?>> readAll(String state);

  Future<CallResult> call(
    String command,
    Map<String, Object?> params, {
    String? id,
  });

  /// The last [n] facts of [fact], oldest first.
  Future<List<FactMessage>> recentFacts(String fact, int n);

  /// Why [state] (of [key]) is as it is (Registry.explain).
  Future<Map<String, Object?>> why(String state, {String? key});

  /// Every layer there is.
  Future<List<Map<String, Object?>>> layers();

  /// The catalog changed: the tools may be others.
  Stream<void> get catalogChanges;
}

/// A board on a registry in this process.
final class LocalBoard implements Board {
  LocalBoard(this.registry, {required this.by});

  final Registry registry;

  /// On whose behalf the agent acts.
  final Principal by;

  @override
  Future<Map<String, Object?>> describe() async => {
    ...registry.describe(),
    'access': {
      for (final d in registry.catalog.whereType<CommandDescriptor>())
        d.name: d.callers.accessOf(by).name,
    },
    'unavailable': {
      for (final d in registry.catalog.whereType<CommandDescriptor>())
        d.name: ?registry.whyUnavailable(d.name),
    },
  };

  @override
  Future<Map<String?, Object?>> readAll(String state) async =>
      registry.readAll(state);

  @override
  Future<CallResult> call(
    String command,
    Map<String, Object?> params, {
    String? id,
  }) => registry.call(command, params, by: by, id: id);

  @override
  Future<List<FactMessage>> recentFacts(String fact, int n) async =>
      registry.recent(fact, n);

  @override
  Future<Map<String, Object?>> why(String state, {String? key}) async =>
      registry.explain(state, key: key);

  @override
  Future<List<Map<String, Object?>>> layers() async => registry.layers();

  @override
  Stream<void> get catalogChanges => registry.catalogChanges;
}
