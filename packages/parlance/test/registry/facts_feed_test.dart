import 'package:fake_async/fake_async.dart';
import 'package:parlance/registry.dart';
import 'package:test/test.dart';

import 'fixture.dart';

void main() {
  late Fixture f;
  late RawFactEmitter raid;

  setUp(() {
    f = Fixture();
    raid = f.r.defineFact(
      FactDescriptor(
        'platform.raid',
        type: const ObjectType({
          'from': Field(TextType()),
          'viewers': Field(IntType(min: 0)),
        }),
        open: true,
      ),
      by: const Principal('plugin', 'twitch'),
    );
  });
  tearDown(() => f.r.dispose());

  group('facts', () {
    test('a repeated id is dropped', () async {
      final seen = <FactMessage>[];
      f.r.facts(fact: 'platform.raid').listen(seen.add);
      expect(raid.emit({'from': 'a', 'viewers': 3}, id: 'r1'), isTrue);
      expect(raid.emit({'from': 'a', 'viewers': 3}, id: 'r1'), isFalse);
      await pumpEventQueue();
      expect(seen.single.id, 'r1');
      expect(seen.single.cause.by, const Principal('plugin', 'twitch'));
    });

    test('ids are forgotten after the window', () {
      fakeAsync((t) {
        final r = Registry(dedupWindow: const Duration(minutes: 10));
        final e = r.defineFact(
          FactDescriptor('x.ping', type: const AnyType()),
          by: owner,
        );
        expect(e.emit(1, id: 'p'), isTrue);
        t.elapse(const Duration(minutes: 11));
        expect(e.emit(1, id: 'p'), isTrue);
      });
    });

    test('payloads are checked', () {
      expect(() => raid.emit({'from': 'a'}), throwsA(isA<TypeMismatch>()));
    });

    test('open facts take more producers; closed ones do not', () async {
      final other = f.r.producer(
        'platform.raid',
        by: const Principal('plugin', 'yt'),
      );
      other.emit({'from': 'b', 'viewers': 1});
      await pumpEventQueue();
      expect(f.r.recent('platform.raid').single.cause.by.id, 'yt');
      f.r.defineFact(
        FactDescriptor('x.closed', type: const AnyType()),
        by: owner,
      );
      expect(() => f.r.producer('x.closed', by: owner), throwsStateError);
      other.dispose();
      expect(
        f.r.factDescriptor('platform.raid'),
        isNotNull,
        reason: 'only the definer removes it',
      );
    });

    test('recent keeps the last ones per fact', () {
      final r = Registry(recentPerFact: 2);
      final e = r.defineFact(
        FactDescriptor('x.n', type: const IntType()),
        by: owner,
      );
      for (var i = 0; i < 5; i++) {
        e.emit(i);
      }
      expect([for (final m in r.recent('x.n')) m.payload], [3, 4]);
      expect([for (final m in r.recent('x.n', 1)) m.payload], [4]);
    });

    test('a batch commits facts and states together, in order', () async {
      final ticks = <Tick>[];
      f.r.ticks.listen(ticks.add);
      f.r.batch(() {
        f.muted.set(true);
        raid.emit({'from': 'a', 'viewers': 1});
      });
      await pumpEventQueue();
      final t = ticks.single;
      expect(t.changes.single.seq, t.from);
      expect(t.facts.single.seq, t.to);
    });
  });

  group('feed', () {
    test('starts with a snapshot, then live ticks', () async {
      f.muted.set(true);
      final items = <FeedItem>[];
      final sub = f.r.feed().listen(items.add);
      await pumpEventQueue();
      f.program.set('main');
      await pumpEventQueue();
      final snap = items.first as Snapshot;
      expect(snap.states['audio.muted'], {null: true});
      expect(snap.factsLost, isFalse);
      expect(items.last, isA<Tick>());
      await sub.cancel();
    });

    test('resumes after a retained seq, without gaps or repeats', () async {
      f.muted.set(true);
      final mark = f.r.seq;
      f.program.set('main');
      raid.emit({'from': 'a', 'viewers': 1});
      final items = <FeedItem>[];
      final sub = f.r.feed(epoch: f.r.epoch, since: mark).listen(items.add);
      await pumpEventQueue();
      f.muted.set(false);
      await pumpEventQueue();
      final ticks = items.cast<Tick>();
      expect(ticks.first.from, mark + 1);
      for (var i = 1; i < ticks.length; i++) {
        expect(ticks[i].from, ticks[i - 1].to + 1);
      }
      await sub.cancel();
    });

    test('a seq no longer retained, or another epoch, starts over', () async {
      final r = Registry(retainTicks: 2);
      final w = r.defineState(
        StateDescriptor('x.n', type: const IntType()),
        by: owner,
      );
      for (var i = 0; i < 5; i++) {
        w.set(i);
      }
      final old = await r.feed(epoch: r.epoch, since: 1).first;
      expect(old, isA<Snapshot>().having((s) => s.factsLost, 'lost', isTrue));
      final other = await r.feed(epoch: 'another', since: 4).first;
      expect(other, isA<Snapshot>());
      final now = r.feed(epoch: r.epoch, since: r.seq);
      final items = <FeedItem>[];
      final sub = now.listen(items.add);
      await pumpEventQueue();
      expect(items, isEmpty, reason: 'nothing new since');
      await sub.cancel();
    });
  });
}
