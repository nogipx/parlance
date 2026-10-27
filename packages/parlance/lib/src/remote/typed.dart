import 'package:rpc_dart/rpc_dart.dart';

import '../registry/messages.dart';
import '../registry/words.dart';
import 'remote.dart';

/// A client's calls and reads through typed words (SPEC §18): what goes
/// over the wire is the same names and JSON.
extension TypedClient on ParlanceClient {
  RemoteCommandOf<P, R> command<P, R>(ICommandWord<P, R> word) =>
      RemoteCommandOf._(this, word);
  RemoteFactOf<T> fact<T>(IFactWord<T> word) => RemoteFactOf._(this, word);
  RemoteQueryOf<P, R> query<P, R>(IQueryWord<P, R> word) =>
      RemoteQueryOf._(this, word);
}

/// A query over remote, typed.
final class RemoteQueryOf<P, R> {
  RemoteQueryOf._(this.client, this.word);

  final ParlanceClient client;
  final IQueryWord<P, R> word;

  /// Asks it; a lost answer is [CallLost], and asking again is safe.
  Future<CallResult<R>> ask(P params, {RpcContext? context}) async =>
      word.answer(
        await client.call(
          word.name,
          word.params.toJson(params),
          context: context,
        ),
      );
}

/// A command over remote, typed.
final class RemoteCommandOf<P, R> {
  RemoteCommandOf._(this.client, this.word);

  final ParlanceClient client;
  final ICommandWord<P, R> word;

  /// As [ParlanceClient.call]: a lost answer is [CallLost]; retry with
  /// its id.
  Future<CallResult<R>> call(
    P params, {
    String? id,
    bool override = false,
    RpcContext? context,
  }) async => (await callAt(
    params,
    id: id,
    override: override,
    context: context,
  )).result;

  /// As [ParlanceClient.callAt]: with the seq a mirror can reach.
  Future<({CallResult<R> result, String? epoch, int? seq})> callAt(
    P params, {
    String? id,
    bool override = false,
    RpcContext? context,
  }) async {
    final r = await client.callAt(
      word.name,
      word.params.toJson(params),
      id: id,
      override: override,
      context: context,
    );
    return (result: word.answer(r.result), epoch: r.epoch, seq: r.seq);
  }
}

/// A fact over remote, typed.
final class RemoteFactOf<T> {
  RemoteFactOf._(this.client, this.word);

  final ParlanceClient client;
  final IFactWord<T> word;

  /// The last [count] the registry keeps, oldest first.
  Future<List<Fact<T>>> recent(int count) async => [
    for (final m in await client.recent(word.name, count))
      Fact(word.shape.fromJson(m.payload), m),
  ];
}

/// A mirror's copy through typed words.
extension TypedMirror on RegistryMirror {
  MirrorStateOf<T> state<T>(IStateWord<T> word) => MirrorStateOf._(this, word);
}

/// A state as a mirror has it, typed.
final class MirrorStateOf<T> {
  MirrorStateOf._(this.mirror, this.word);

  final RegistryMirror mirror;
  final IStateWord<T> word;

  T? read({String? key}) => word.decode(mirror.read(word.name, key: key));

  Map<String?, T> readAll() => {
    for (final e in mirror.readAll(word.name).entries)
      if (e.value != null) e.key: word.shape.fromJson(e.value),
  };
}
