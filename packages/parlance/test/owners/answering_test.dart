import 'dart:async';

import 'package:parlance/schema.dart';
import 'package:parlance/tools.dart';
import 'package:parlance/src/registry/registry.dart' show RawRegistry;
import 'package:test/test.dart';

part 'answering_test.g.dart';

/// An owner's handler knows who it answers (`caller`), may act on its own
/// in it (`apart`), and writes as one tick outside a handler (`batch`),
/// with nothing of the call passed to it.
@Vocabulary('room')
abstract class Room {
  @StateWord('heat')
  int get heat;

  @StateWord('lamp')
  bool get lamp;

  @CommandWord('warm', callers: Callers({'user': Access.allow}))
  void warm();
}

final class _Room extends RoomOwnerBase {
  Principal? warmedBy;
  final cooled = Completer<void>();

  @override
  void warm() {
    warmedBy = by;
    heat.set(25);
    // Cools on its own later: not in answer to the call.
    apart(
      () => Timer(Duration.zero, () {
        heat.set(20);
        cooled.complete();
      }),
    );
  }
}

void main() {
  const user = Principal('user', 'ann');

  test(
    'a handler knows who it answers; what it does apart is its own',
    () async {
      final r = Registry();
      addTearDown(r.dispose);
      final room = _Room();
      r.participant(const Principal('room'), owners: [room]);
      expect(room.by, isNull, reason: 'outside a handler');
      await r.participant(user).call('room.warm', {}, id: 'w1');
      expect(room.warmedBy, user);
      expect(r.explain('room.heat').change!.cause.parent, 'w1');
      await room.cooled.future;
      expect(r.read('room.heat'), 20);
      expect(r.explain('room.heat').change!.cause.parent, isNull);
    },
  );

  test('batch writes as one tick', () async {
    final r = Registry();
    addTearDown(r.dispose);
    final room = _Room();
    r.participant(const Principal('room'), owners: [room]);
    await pumpEventQueue();
    final ticks = <Tick>[];
    final sub = r.ticks.listen(ticks.add);
    room.batch(() {
      room.heat.set(22);
      room.lamp.set(true);
    });
    await pumpEventQueue();
    await sub.cancel();
    expect(ticks.single.changes, hasLength(2));
  });
}
