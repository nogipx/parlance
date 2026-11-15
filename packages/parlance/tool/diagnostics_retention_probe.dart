/// Forced-GC checks for diagnostic history. Run with:
/// fvm dart --enable-vm-service=0 run tool/diagnostics_retention_probe.dart
library;

import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:parlance/app.dart';
import 'package:parlance/tools.dart';

final _held = <Object>[];
final _checks = <({String name, WeakReference<Object> weak, bool collected})>[];

final class _Owner {
  final payload = List<String>.unmodifiable(
    List.generate(4096, (i) => 'value-$i'),
  );
  void handle() {
    if (payload.isEmpty) throw StateError('empty');
  }
}

/// The probe's values are already immutable; keep their exact native identity.
final class _NativeShape extends Shape<List<String>> {
  @override
  ValueType<Object?> get type => const ListType(TextType());
  @override
  Object? toJson(List<String> value) => value;
  @override
  List<String> fromJson(Object? json) =>
      List<String>.unmodifiable((json! as List).cast<String>());
  @override
  List<String> check(List<String> value, {List<String>? was}) => value;
  @override
  bool equals(List<String> a, List<String> b) => identical(a, b);
  @override
  int weigh(List<String> value) => value.length * 16;
}

@pragma('vm:never-inline')
void _controls() {
  final dead = Object();
  final live = Object();
  _checks.add((
    name: 'unreferenced control',
    weak: WeakReference(dead),
    collected: true,
  ));
  _checks.add((
    name: 'retained control',
    weak: WeakReference(live),
    collected: false,
  ));
  _held.add(live);
}

@pragma('vm:never-inline')
Future<void> _participantGone() async {
  final host = Host(
    limits: const HostLimits(retainTicks: 4, retainBytes: 4096),
  );
  final participant = host.participant(
    const Principal('source'),
    vocabularies: [const WordSet.open('data')],
  );
  final owner = _Owner();
  _checks.add((
    name: 'withdrawn handler owner',
    weak: WeakReference(owner),
    collected: true,
  ));
  _checks.add((
    name: 'evicted native payload',
    weak: WeakReference(owner.payload),
    collected: true,
  ));
  participant.raw.defineCommand(
    CommandDescriptor('data.run', callers: Callers.anyone),
    (_) => owner.handle(),
  );
  final state = participant.raw.defineState(
    StateDescriptor('data.value', type: const ListType(TextType())),
    shape: _NativeShape(),
  );
  state.set(owner.payload);
  await participant.raw.call('source/data.run', {});
  participant.dispose();
  final other = host.participant(
    const Principal('other'),
    vocabularies: [const WordSet.open('other')],
  );
  final tick = other.raw.defineState(
    StateDescriptor('other.tick', type: const IntType()),
  );
  other.raw.defineCommand(
    CommandDescriptor('other.run', callers: Callers.anyone),
    (_) {},
  );
  for (var i = 0; i < 100; i++) {
    tick.set(i);
    await other.raw.call('other/other.run', {});
  }
  if (host.registry.diagnostics.length > 4) {
    throw StateError('unbounded metadata');
  }
  _held.add(host);
}

@pragma('vm:never-inline')
Future<void> _hostGone() async {
  final host = Host();
  final owner = _Owner();
  final p = host.participant(
    const Principal('source'),
    vocabularies: [const WordSet.open('data')],
  );
  _checks.add((
    name: 'disposed host owner',
    weak: WeakReference(owner),
    collected: true,
  ));
  p.raw.defineCommand(
    CommandDescriptor(
      'data.run',
      callers: Callers.anyone,
      params: const RecordType({'data': Field(ListType(TextType()))}),
    ),
    (_) => owner.handle(),
  );
  await p.raw.call('source/data.run', {'data': owner.payload}, id: 'retained');
  final kept = host.registry.callRecord('source#retained')!.params['data']!;
  _checks.add((
    name: 'disposed dedup payload',
    weak: WeakReference(kept),
    collected: true,
  ));
  await host.dispose();
  if (host.registry.diagnostics.isNotEmpty ||
      host.registry.running.isNotEmpty ||
      host.registry.pending.isNotEmpty) {
    throw StateError('disposed registry retained diagnostic state');
  }
  _held.add(host);
}

@pragma('vm:never-inline')
Future<void> _pausedJournalGone() async {
  final host = Host();
  final p = host.participant(
    const Principal('source'),
    vocabularies: [const WordSet.open('data')],
  );
  final payload = _Owner().payload;
  _checks.add((
    name: 'disposed paused journal payload',
    weak: WeakReference(payload),
    collected: true,
  ));
  final state = p.raw.defineState(
    StateDescriptor('data.value', type: const ListType(TextType())),
    shape: _NativeShape(),
  );
  host.registry.captureStateWrites(['source/data.value']);
  final sub = host.registry.journal.listen((_) {}, onError: (Object _) {});
  sub.pause();
  state.set(payload);
  await host.dispose();
  _held.addAll([host, sub]);
}

final class _Vm {
  _Vm(this.socket) {
    socket.listen((data) {
      final message = jsonDecode(data as String) as Map<String, dynamic>;
      if (message['id'] case final String id) {
        _pending.remove(id)?.complete(message);
      }
    });
  }
  final WebSocket socket;
  final _pending = <String, Completer<Map<String, dynamic>>>{};
  var _id = 0;
  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, Object?> params = const {},
  ]) async {
    final id = '${++_id}';
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    socket.add(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        'params': params,
      }),
    );
    final message = await completer.future;
    if (message.containsKey('error')) throw StateError('$message');
    return (message['result'] as Map).cast<String, dynamic>();
  }
}

Future<void> main() async {
  final info = await Service.getInfo();
  final uri = info.serverUri;
  if (uri == null) throw StateError('run with --enable-vm-service=0');
  final socket = await WebSocket.connect(
    uri.replace(scheme: 'ws', path: '${uri.path}ws').toString(),
  );
  final vm = _Vm(socket);
  try {
    _controls();
    await _participantGone();
    await _hostGone();
    await _pausedJournalGone();
    final isolate = ((await vm.call('getVM'))['isolates'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((e) => e['name'] == 'main')['id'];
    for (var i = 0; i < 4; i++) {
      await Future<void>.delayed(Duration.zero);
      await vm.call('getAllocationProfile', {'isolateId': isolate, 'gc': true});
    }
    final failed = [
      for (final c in _checks)
        if ((c.weak.target == null) != c.collected) c.name,
    ];
    if (failed.isNotEmpty) {
      throw StateError('retained unexpectedly: ${failed.join(', ')}');
    }
    stdout.writeln(
      'diagnostics retention: ${_checks.length} forced-GC checks passed',
    );
    final reloaded = await vm.call('reloadSources', {'isolateId': isolate});
    if (reloaded['success'] != true) {
      throw StateError('hot reload failed: $reloaded');
    }
    stdout.writeln('diagnostics hot reload: passed');
  } finally {
    for (final object in _held) {
      if (object is Host) await object.dispose();
      if (object is StreamSubscription<JournalEntry>) await object.cancel();
    }
    _held.clear();
    await socket.close();
  }
}
