import 'dart:async';

import '../registry/messages.dart';
import '../remote/remote.dart';
import 'board.dart';

/// A board on a registry reached over remote: calls go through [client],
/// states and recent facts are read from [mirror], which follows the
/// client's feed. On whose behalf it acts is the host's to say: the
/// session's principal.
final class RemoteBoard implements Board {
  RemoteBoard(this.client, this.mirror);

  final SwitchboardClient client;
  final RegistryMirror mirror;

  @override
  Future<Map<String, Object?>> describe() => client.describe();

  @override
  Future<Map<String?, Object?>> readAll(String state) async =>
      mirror.readAll(state);

  @override
  Future<CallResult> call(
    String command,
    Map<String, Object?> params, {
    String? id,
  }) => client.call(command, params, id: id);

  @override
  Future<List<FactMessage>> recentFacts(String fact, int n) async =>
      mirror.recent(fact, n);

  @override
  Future<Map<String, Object?>> why(String state, {String? key}) =>
      client.why(state, key: key);

  @override
  Future<List<Map<String, Object?>>> layers() => client.layers();

  /// The mirror's changes stand for the catalog's: a describe after one
  /// tells the same as it would after a catalog change.
  @override
  Stream<void> get catalogChanges {
    var last = '';
    return mirror.changes.asyncExpand((_) async* {
      final now = '${mirror.catalog['descriptors']}';
      if (now != last) {
        last = now;
        yield null;
      }
    });
  }
}
