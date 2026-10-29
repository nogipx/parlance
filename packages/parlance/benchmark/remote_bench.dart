/// The registry across a connection (SPEC §14): a guest calls the host,
/// writes its own words, and hears the host's; the host tells many guests
/// what changed. Over a channel that encodes each message as a connection
/// does (`wire`), and over one in memory that does not (`memory`), so the
/// cost of the protocol shows apart from the cost of the encoding.
///
/// Run: `fvm dart compile exe benchmark/remote_bench.dart -o .tmp/remote && .tmp/remote`.
library;

import 'dart:async';

import 'package:parlance/participant.dart';
import 'package:parlance/registry.dart';
import 'package:parlance/remote.dart';
import 'package:parlance/src/registry/registry.dart' show RawRegistry;
import 'package:rpc_dart/rpc_dart.dart';

const studio = Principal('studio');

String us(int micros, int n) => '${(micros / n).toStringAsFixed(1)} us';

/// [what] in a column, then [result].
String row(String what, int width, String result) =>
    '${what.padRight(width)}$result';

/// A host: a registry whose studio owns [words] states of its own, a
/// command answered at once, and a kind of [entities] scenes.
final class Host {
  Host({int words = 0, int entities = 10}) {
    final p = r.participant(
      studio,
      vocabularies: [const WordSet.open('studio')],
    );
    program = p.defineState(
      StateDescriptor('studio.program', type: const IntType()),
    );
    for (var i = 0; i < words; i++) {
      p.defineState(
        StateDescriptor(
          'studio.s$i',
          type: const ObjectType({'v': Field(IntType())}),
          meta: const {'label': 'a state of the studio, with a label'},
        ),
      );
    }
    p.defineCommand(
      CommandDescriptor(
        'studio.ping',
        params: const ObjectType({'n': Field(IntType())}),
        callers: Callers.only(['widlet']),
      ),
      (c) => c.params['n'],
    );
    scenes = [for (var i = 0; i < entities; i++) EntityRef('scene$i')];
    p.registerKind(EntityKind('scene', list: () => scenes));
    this.p = p;
  }

  final r = Registry();
  late final LocalParticipant p;
  late final IStateHandle program;
  late List<EntityRef> scenes;
  final List<RpcPeerEndpoint> _ends = [];

  /// A guest joined over a channel of its own; [features] stand in for an
  /// older host.
  Future<RemoteParticipant> guest(
    String id, {
    required bool wire,
    Set<String>? features,
  }) async {
    final (g, h) = wire
        ? RpcChannelTransport.pair()
        : RpcChannelTransport.memoryPair();
    final host = RpcPeerEndpoint(transport: h);
    r
        .participant(
          Principal('widlet', id),
          vocabularies: [WordSet.open('g$id')],
        )
        .serve(host, limits: SessionLimits.none, features: features);
    host.start();
    final own = RpcPeerEndpoint(transport: g)..start();
    _ends.addAll([host, own]);
    final p = await RemoteParticipant.over(own);
    await p.settle();
    return p;
  }

  Future<void> close() async {
    for (final e in _ends) {
      await e.close();
    }
    await r.dispose();
  }
}

/// A call the host answers at once: one waited for at a time, and many
/// sent together.
Future<void> calls(bool wire) async {
  final host = Host();
  final g = await host.guest('a', wire: wire);
  for (var i = 0; i < 200; i++) {
    await g.call('studio.ping', {'n': i});
  }
  const n = 2000;
  final sw = Stopwatch()..start();
  for (var i = 0; i < n; i++) {
    await g.call('studio.ping', {'n': i});
  }
  final one = sw.elapsedMicroseconds;
  sw
    ..reset()
    ..start();
  await Future.wait([
    for (var i = 0; i < n; i++) g.call('studio.ping', {'n': i}),
  ]);
  print(
    'call, answered at once:    ${us(one, n)} each waited for, '
    '${us(sw.elapsedMicroseconds, n)} each of $n sent together',
  );
  await g.close();
  await host.close();
}

/// The guest writes a state of its own: one write the host has before it
/// goes on, and many written as they come, the host having them all.
Future<void> writes(bool wire) async {
  final host = Host();
  final g = await host.guest('a', wire: wire);
  final seen = g.defineState(
    StateDescriptor('ga.seen', type: const IntType(), key: 'viewer'),
  );
  final level = g.defineState(
    StateDescriptor('ga.level', type: const IntType()),
  );
  await g.flush();
  for (var i = 0; i < 200; i++) {
    level.set(i);
    await g.flush();
  }
  const n = 2000;
  final sw = Stopwatch()..start();
  for (var i = 0; i < n; i++) {
    level.set(i);
    await g.flush();
  }
  final one = sw.elapsedMicroseconds;
  const keys = 20000;
  sw
    ..reset()
    ..start();
  for (var i = 0; i < keys; i++) {
    seen.set(i, key: 'v${i % 5000}');
    // As a guest's code goes: a turn of the event loop now and then.
    if (i % 100 == 0) await Future<void>.delayed(Duration.zero);
  }
  await g.flush();
  final many = sw.elapsedMicroseconds;
  if (host.r.read('ga.seen', key: 'v4999') != keys - 1) {
    throw StateError('the host does not have the last write');
  }
  print(
    'guest writes its own:      ${us(one, n)} each flushed, '
    '${us(many, keys)} each of $keys as they come',
  );
  await g.close();
  await host.close();
}

/// The host writes a state [n] guests watch: how long until every one of
/// them has the value.
Future<void> fanOut(bool wire, int n) async {
  final host = Host();
  final guests = [
    for (var i = 0; i < n; i++) await host.guest('$i', wire: wire),
  ];
  var want = -1;
  var heard = 0;
  Completer<void>? all;
  final subs = [
    for (final g in guests)
      g.watch('studio.program').listen((v) {
        if (v == want && ++heard == n) all?.complete();
      }),
  ];
  Future<void> once(int v) async {
    want = v;
    heard = 0;
    all = Completer();
    host.program.set(v);
    await all!.future;
  }

  for (var i = 0; i < 20; i++) {
    await once(i);
  }
  const rounds = 200;
  final sw = Stopwatch()..start();
  for (var i = 0; i < rounds; i++) {
    await once(1000 + i);
  }
  print(
    row(
      'host writes, $n watch${n == 1 ? 'es' : ''}:',
      27,
      '${us(sw.elapsedMicroseconds, rounds)} until every guest has it',
    ),
  );
  for (final s in subs) {
    await s.cancel();
  }
  for (final g in guests) {
    await g.close();
  }
  await host.close();
}

/// A scene added while [n] guests follow a catalog of [words] words: how
/// long until every one of them has it, told as the one kind (`kinds`) or
/// as the whole catalog.
Future<void> entities(
  bool wire,
  int n,
  int words, {
  required bool kinds,
}) async {
  final host = Host(words: words);
  final guests = [
    for (var i = 0; i < n; i++)
      await host.guest(
        '$i',
        wire: wire,
        features: kinds ? null : const {'built'},
      ),
  ];
  var heard = 0;
  var wantLen = 0;
  Completer<void>? all;
  final subs = [
    for (final g in guests)
      g.catalogChanges.listen((_) {
        final scene = (g.catalog['kinds'] as List).firstWhere(
          (k) => (k as Map)['name'] == 'scene',
        );
        if (((scene as Map)['entities'] as List).length == wantLen &&
            ++heard == n) {
          all?.complete();
        }
      }),
  ];
  Future<void> once() async {
    host.scenes = [...host.scenes, EntityRef('scene${host.scenes.length}')];
    wantLen = host.scenes.length;
    heard = 0;
    all = Completer();
    host.p.entitiesChanged('scene');
    await all!.future;
  }

  for (var i = 0; i < 5; i++) {
    await once();
  }
  const rounds = 50;
  final sw = Stopwatch()..start();
  for (var i = 0; i < rounds; i++) {
    await once();
  }
  print(
    row(
      'a scene, $n guests, $words words, '
          '${kinds ? 'the kind' : 'the catalog'}:',
      46,
      '${us(sw.elapsedMicroseconds, rounds)} until every guest has it',
    ),
  );
  for (final s in subs) {
    await s.cancel();
  }
  for (final g in guests) {
    await g.close();
  }
  await host.close();
}

Future<void> main() async {
  for (final wire in [true, false]) {
    print('--- ${wire ? 'wire (encoded)' : 'memory'} ---');
    await calls(wire);
    await writes(wire);
    for (final n in [1, 10, 100]) {
      await fanOut(wire, n);
    }
    for (final kinds in [true, false]) {
      await entities(wire, 20, 200, kinds: kinds);
    }
  }
}
