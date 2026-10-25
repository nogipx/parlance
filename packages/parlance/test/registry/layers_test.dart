import 'package:fake_async/fake_async.dart';
import 'package:parlance/registry.dart';
import 'package:test/test.dart';

import 'fixture.dart';

void main() {
  late Fixture f;
  late List<LayerEvent> events;

  setUp(() {
    f = Fixture();
    events = [];
    f.r.layerEvents.listen(events.add);
  });
  tearDown(() => f.r.dispose());

  LayerHandle hold(
    Object? value, {
    String owner = 'a',
    int priority = 0,
    Principal by = const Principal('link', 'a'),
  }) => f.r.pushLayer(
    'audio.muted',
    value: value,
    owner: owner,
    by: by,
    priority: priority,
  );

  test(
    'a layer dispatches its value; dropping it brings the base back',
    () async {
      f.muted.set(false);
      final h = hold(true);
      await pumpEventQueue();
      expect(f.r.read('audio.muted'), true);
      h.dispose();
      await pumpEventQueue();
      expect(f.r.read('audio.muted'), false);
      expect(f.mutes, [true, false]);
      expect(events.single.outcome, LayerOutcome.removed);
      expect(h.active, isFalse);
    },
  );

  test('the top layer wins: priority first, then the latest', () async {
    f.r.pushLayer(
      'audio.gain',
      key: 'mic',
      value: -10,
      owner: 'low',
      by: Principal.system,
      priority: 0,
    );
    final high = f.r.pushLayer(
      'audio.gain',
      key: 'mic',
      value: -20,
      owner: 'high',
      by: Principal.system,
      priority: 5,
    );
    f.r.pushLayer(
      'audio.gain',
      key: 'mic',
      value: -30,
      owner: 'late',
      by: Principal.system,
      priority: 0,
    );
    await pumpEventQueue();
    expect(f.r.read('audio.gain', key: 'mic'), -20);
    high.dispose();
    await pumpEventQueue();
    expect(
      f.r.read('audio.gain', key: 'mic'),
      -30,
      reason: 'latest among equals',
    );
  });

  test('layers end in any order without stepping on each other', () async {
    f.muted.set(false);
    final a = hold(true, owner: 'a');
    final b = hold(true, owner: 'b');
    await pumpEventQueue();
    a.dispose();
    await pumpEventQueue();
    expect(f.r.read('audio.muted'), true, reason: 'b still holds');
    b.dispose();
    await pumpEventQueue();
    expect(f.r.read('audio.muted'), false);
  });

  test('an explicit set clears the layers and becomes the base', () async {
    f.muted.set(false);
    final h = hold(true);
    await pumpEventQueue();
    await f.r.call('audio.mute', {'on': false}, by: user);
    await pumpEventQueue();
    expect(h.active, isFalse);
    expect(events.single.outcome, LayerOutcome.overridden);
    expect(f.r.read('audio.muted'), false);
    expect(f.mutes, [true, false], reason: 'nothing dispatched after');
  });

  test("the owner's own change clears them too; an echo does not", () async {
    f.muted.set(false);
    final h = hold(true);
    await pumpEventQueue();
    f.muted.set(true);
    await pumpEventQueue();
    expect(h.active, isTrue, reason: 'same value as the layer');
    f.muted.set(false);
    await pumpEventQueue();
    expect(h.active, isFalse);
    expect(events.single.outcome, LayerOutcome.overridden);
  });

  test('a refused dispatch keeps the layer and says why', () async {
    f.r.addGuard('stay', (c) => c.layerDispatch ? 'not now' : null);
    final h = hold(true);
    await pumpEventQueue();
    expect(h.active, isTrue);
    expect(events.single.outcome, LayerOutcome.refused);
    expect(events.single.reason, 'not now');
    expect(f.r.has('audio.muted'), isFalse);
  });

  test(
    'a dispatch goes on behalf of the top layer, with its owner in the chain',
    () async {
      final records = <CallRecord>[];
      f.r.calls.listen(records.add);
      hold(true, owner: 'link-x', by: const Principal('link', 'x'));
      await pumpEventQueue();
      final r = records.single;
      expect(r.layerDispatch, isTrue);
      expect(r.cause.by, const Principal('link', 'x'));
      expect(r.cause.chain, ['link-x']);
    },
  );

  test('a layer value is checked; a state without a setter takes none', () {
    expect(() => hold('yes'), throwsA(isA<TypeMismatch>()));
    final w = f.r.defineState(
      StateDescriptor('x.plain', type: const IntType()),
      by: owner,
    );
    expect(
      () =>
          f.r.pushLayer('x.plain', value: 1, owner: 'a', by: Principal.system),
      throwsStateError,
    );
    w.dispose();
  });

  test('ttl drops the layer', () {
    fakeAsync((t) {
      final x = Fixture();
      final ev = <LayerEvent>[];
      x.r.layerEvents.listen(ev.add);
      x.muted.set(false);
      x.r.pushLayer(
        'audio.muted',
        value: true,
        owner: 'a',
        by: Principal.system,
        ttl: const Duration(seconds: 15),
      );
      t.flushMicrotasks();
      expect(x.r.read('audio.muted'), true);
      t.elapse(const Duration(seconds: 16));
      expect(x.r.read('audio.muted'), false);
      expect(ev.single.outcome, LayerOutcome.expired);
    });
  });

  test('layers survive a restart as leases', () {
    fakeAsync((t) {
      final before = Fixture();
      before.muted.set(false);
      before.r.pushLayer(
        'audio.muted',
        value: true,
        owner: 'break',
        by: Principal.system,
      );
      before.r.pushLayer(
        'audio.gain',
        key: 'mic',
        value: -40,
        owner: 'gone',
        by: Principal.system,
      );
      before.r.pushLayer(
        'audio.gain',
        key: 'music',
        value: -5,
        owner: 'short',
        by: Principal.system,
        ttl: const Duration(seconds: 5),
      );
      t.flushMicrotasks();
      final saved = before.r.exportLayers();

      t.elapse(const Duration(seconds: 10));
      final after = Fixture();
      final ev = <LayerEvent>[];
      after.r.layerEvents.listen(ev.add);
      after.muted.set(false);
      after.gain.set(0, key: 'mic');
      after.r.importLayers(saved);
      t.flushMicrotasks();
      expect(after.r.read('audio.muted'), true, reason: 'applied at once');
      expect(after.r.read('audio.gain', key: 'mic'), -40);
      expect(
        after.r.read('audio.gain', key: 'music'),
        isNull,
        reason: 'expired, not restored',
      );

      final mine = after.r.claim('break');
      expect(mine, hasLength(1));
      t.elapse(const Duration(seconds: 31));
      expect(ev.map((e) => (e.owner, e.outcome)), [
        ('gone', LayerOutcome.unclaimed),
      ]);
      expect(
        after.r.read('audio.gain', key: 'mic'),
        0,
        reason: 'its base came back',
      );
      expect(mine.single.active, isTrue);
      mine.single.dispose();
      t.flushMicrotasks();
      expect(after.r.read('audio.muted'), false);
    });
  });

  test('removing the setter orphans the layers', () async {
    final x = Registry(onError: (e, s) => throw e);
    final w = x.defineState(
      StateDescriptor('x.on', type: const BoolType()),
      by: owner,
    );
    final cmd = x.defineCommand(
      CommandDescriptor(
        'x.set',
        params: const ObjectType({'value': Field(BoolType())}),
        callers: Callers.only(['system']),
        sets: const Sets('x.on'),
      ),
      (c) => w.set(c.params['value']),
    );
    final ev = <LayerEvent>[];
    x.layerEvents.listen(ev.add);
    x.pushLayer('x.on', value: true, owner: 'a', by: Principal.system);
    cmd.dispose();
    await pumpEventQueue();
    expect(ev.single.outcome, LayerOutcome.orphaned);
    expect(x.setterOf('x.on'), isNull);
  });

  test('effective tells the held value or the base', () async {
    f.muted.set(false);
    expect(f.r.effective('audio.muted'), (has: true, value: false));
    hold(true);
    expect(f.r.effective('audio.muted').value, true);
    expect(f.r.effective('audio.gain', key: 'mic').has, isFalse);
  });
}
