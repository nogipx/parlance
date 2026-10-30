import 'dart:async';

import 'package:parlance/tools.dart';
import 'package:parlance/src/registry/registry.dart' show RawRegistry;
import 'package:test/test.dart';
import 'package:parlance/src/participant/owner.dart' show Owner;

/// An owner's handler knows who it answers (`caller`), may act on its own
/// in it (`apart`), and writes as one tick outside a handler (`batch`),
/// with nothing of the call passed to it.
enum _State<T> implements IStateWord<T> {
  heat<int>('room.heat', Plain(IntType())),
  lamp<bool>('room.lamp', Plain(BoolType()));

  const _State(this.name, this.shape);
  @override
  final String name;
  @override
  final Shape<T> shape;
  @override
  String? get key => null;
}

enum _Command<P, R> implements ICommandWord<P, R> {
  warm<(), void>('room.warm', RecordShape.none, null);

  const _Command(this.name, this.params, this.returns);
  @override
  final String name;
  @override
  final RecordShape<P> params;
  @override
  final Shape<R>? returns;
}

final class _Room extends Owner {
  late final IStateWriterOf<int> heat;
  late final IStateWriterOf<bool> lamp;
  Principal? warmedBy;
  final cooled = Completer<void>();

  @override
  void define(IRawParticipant p) {
    heat = keep(p.state(_State.heat).define());
    lamp = keep(p.state(_State.lamp).define());
    keep(
      p.command(_Command.warm).define((_) {
        warmedBy = caller;
        heat.set(25);
        // Cools on its own later: not in answer to the call.
        apart(
          () => Timer(Duration.zero, () {
            heat.set(20);
            cooled.complete();
          }),
        );
      }, callers: Callers.only(['user'])),
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
      r.participant(
        const Principal('room'),
        vocabularies: [WordSet.open('room')],
        owners: [room],
      );
      expect(room.caller, isNull, reason: 'outside a handler');
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
    r.participant(
      const Principal('room'),
      vocabularies: [WordSet.open('room')],
      owners: [room],
    );
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
