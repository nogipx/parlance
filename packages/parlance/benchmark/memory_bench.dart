/// What a registry keeps in memory as a state is rewritten: its retained
/// ticks hold each change's value and the previous one.
///
/// Run: `fvm dart compile exe benchmark/memory_bench.dart -o .tmp/mem && .tmp/mem`.
library;

import 'dart:io';

import 'package:parlance/tools.dart';
import 'package:parlance/src/registry/registry.dart' show RawRegistry;

const host = Principal('host', 'bench');

Map<String, Object?> doc(int sections, int version) => {
  'version': version,
  'sections': [
    for (var s = 0; s < sections; s++)
      {
        'title': 'section $s',
        'checks': [
          for (var c = 0; c < 20; c++)
            {
              'id': 's$s-c$c',
              'text': 'check $c of section $s',
              'passed': false,
            },
        ],
      },
  ],
};

int mb() => ProcessInfo.currentRss ~/ (1024 * 1024);

Future<void> run(int retainTicks, int writes) async {
  final r = Registry(retainTicks: retainTicks, onError: (e, _) => throw e);
  final w = r.defineState(
    StateDescriptor('task', type: const AnyType()),
    by: host,
  );
  final before = mb();
  for (var i = 0; i < writes; i++) {
    w.set(doc(1000, i));
    if (i % 50 == 0) await Future<void>.delayed(Duration.zero);
  }
  await Future<void>.delayed(Duration.zero);
  print(
    'retainTicks $retainTicks, $writes writes of ~2 MB: '
    'rss +${mb() - before} MB',
  );
  await r.dispose();
}

/// The same documents made and held one at a time, with no registry: what
/// the app itself costs.
Future<void> bare(int writes) async {
  final before = mb();
  Object? held;
  for (var i = 0; i < writes; i++) {
    held = freezeJson(doc(1000, i));
    if (i % 50 == 0) await Future<void>.delayed(Duration.zero);
  }
  print(
    'no registry, $writes docs held one at a time: rss +${mb() - before} MB',
  );
  if (held == null) print('');
}

Future<void> main(List<String> args) async {
  if (args.first == 'bare') return bare(int.parse(args[1]));
  await run(int.parse(args[0]), int.parse(args[1]));
}
