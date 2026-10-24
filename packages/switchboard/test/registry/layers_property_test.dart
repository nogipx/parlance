import 'dart:math';

import 'package:switchboard/registry.dart';
import 'package:test/test.dart';

import 'fixture.dart';

/// Random pushes, drops and explicit sets against a plain model of SPEC §8:
/// after things settle, the value is the top layer's, or the last explicit
/// value (the base) when no layer is left.
void main() {
  for (var seed = 0; seed < 40; seed++) {
    test('layers settle to the model, seed $seed', () async {
      final rnd = Random(seed);
      final f = Fixture();
      final handles = <LayerHandle>[];
      final model = <({String id, int value, int priority, int order})>[];
      var order = 0;
      num base = 0;
      await f.r.call('audio.gain.set', {'input': 'mic', 'db': 0}, by: user);

      num expected() {
        if (model.isEmpty) return base;
        var top = model.first;
        for (final l in model) {
          if (l.priority > top.priority ||
              (l.priority == top.priority && l.order > top.order)) {
            top = l;
          }
        }
        return top.value;
      }

      for (var step = 0; step < 60; step++) {
        final roll = rnd.nextInt(10);
        if (roll < 5) {
          final value = -rnd.nextInt(60);
          final priority = rnd.nextInt(3);
          final h = f.r.pushLayer(
            'audio.gain',
            key: 'mic',
            value: value,
            owner: 'o$step',
            by: Principal.system,
            priority: priority,
          );
          handles.add(h);
          model.add((
            id: h.id,
            value: value,
            priority: priority,
            order: order++,
          ));
        } else if (roll < 8 && handles.isNotEmpty) {
          final h = handles.removeAt(rnd.nextInt(handles.length));
          h.dispose();
          model.removeWhere((l) => l.id == h.id);
        } else {
          final value = -rnd.nextInt(60);
          await f.r.call('audio.gain.set', {
            'input': 'mic',
            'db': value,
          }, by: user);
          base = value;
          model.clear();
          handles.clear();
        }
        await pumpEventQueue();
        expect(
          f.r.read('audio.gain', key: 'mic'),
          expected(),
          reason: 'step $step',
        );
        for (final h in handles) {
          expect(h.active, isTrue, reason: 'step $step');
        }
      }
      await f.r.dispose();
    });
  }
}
