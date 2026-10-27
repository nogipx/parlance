import '../registry/messages.dart';
import '../remote/remote.dart';
import 'board.dart';

/// A board on a registry reached over remote: calls and recent facts go
/// through [client], states are read from [mirror], which follows the
/// client's feed. On whose behalf it acts is the host's to say: the
/// session's principal.
final class RemoteBoard implements IBoard {
  RemoteBoard(
    this.client,
    this.mirror, {
    this.catchUp = const Duration(seconds: 2),
  });

  final ParlanceClient client;
  final RegistryMirror mirror;

  /// How long a call waits for the mirror to show what it wrote.
  final Duration catchUp;

  // The position the last call answered at, while the mirror has not
  // reached it: reads then say so rather than answer what is older.
  ({String epoch, int seq})? _behind;

  @override
  Future<Map<String, Object?>> describe() => client.describe();

  /// The copy's values; while it does not follow the registry (the
  /// connection dropped), [BoardOffline] rather than what it had.
  @override
  Future<Map<String?, Object?>> readAll(String state) async {
    if (!mirror.synced) throw BoardOffline(mirror.seq);
    if (_behind case (:final epoch, :final seq)?) {
      if (!await mirror.reach(epoch, seq, timeout: catchUp)) {
        throw BoardBehind(mirror.seq, seq);
      }
      _behind = null;
    }
    return mirror.readAll(state);
  }

  /// The call, answered once the copy shows what it wrote, or after
  /// [catchUp]: then reads throw [BoardBehind] until the copy catches up,
  /// so a read after a call never answers what came before it.
  @override
  Future<CallResult<Object?>> call(
    String command,
    Map<String, Object?> params, {
    String? id,
  }) async {
    final r = await client.callAt(command, params, id: id);
    if (r.epoch case final epoch?) {
      final seq = r.seq!;
      _behind = await mirror.reach(epoch, seq, timeout: catchUp)
          ? null
          : (epoch: epoch, seq: seq);
    }
    return r.result;
  }

  @override
  Future<List<FactMessage>> recentFacts(String fact, int n) =>
      client.recent(fact, n);

  @override
  Future<Explanation> why(String state, {String? key}) =>
      client.why(state, key: key);

  @override
  Stream<void> get catalogChanges => mirror.catalogChanges;
}
