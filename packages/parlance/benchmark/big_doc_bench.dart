import 'dart:convert';
import 'package:parlance/registry.dart';
import 'package:parlance/src/registry/registry.dart' show RawRegistry;

const host = Principal('host', 'bench');

/// An acceptance task: sections of checks, each with a few fields.
Map<String, Object?> doc(int sections, int version) => {
  'id': 'task-1',
  'version': version,
  'sections': [
    for (var s = 0; s < sections; s++)
      {
        'title': 'section $s',
        'checks': [
          for (var c = 0; c < 20; c++)
            {
              'id': 's$s-c$c',
              'text': 'check $c of section $s, what to look at',
              'passed': c.isEven,
              'note': null,
              'tags': ['a', 'b'],
            },
        ],
      },
  ],
};

void main() {
  for (final sections in [100, 1000, 2000]) {
    final r = Registry(onError: (e, _) => throw e);
    final w = r.defineState(
      StateDescriptor('task', type: const AnyType()),
      by: host,
    );
    final a = doc(sections, 1), b = doc(sections, 2);
    final kb = utf8.encode(jsonEncode(a)).length ~/ 1024;
    w.set(a);
    final sw = Stopwatch()..start();
    for (var i = 0; i < 10; i++) {
      w.set(i.isEven ? b : a);
    }
    final write = sw.elapsedMicroseconds / 10 / 1000;
    sw
      ..reset()
      ..start();
    for (var i = 0; i < 10; i++) {
      jsonDecode(jsonEncode(a));
    }
    final codec = sw.elapsedMicroseconds / 10 / 1000;
    sw
      ..reset()
      ..start();
    for (var i = 0; i < 1000; i++) {
      r.read('task');
    }
    final read = sw.elapsedMicroseconds / 1000;
    print(
      '$kb KB: write ${write.toStringAsFixed(1)} ms, raw read ${read.toStringAsFixed(2)} us, '
      'jsonEncode+Decode for scale ${codec.toStringAsFixed(1)} ms',
    );
  }
}
