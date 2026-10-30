import 'package:fake_async/fake_async.dart';
import 'package:parlance/tools.dart';
import 'package:test/test.dart';

import 'fixture.dart';
import 'package:parlance/src/registry/registry.dart' show RawRegistry;

void main() {
  late Fixture f;
  late RawFactEmitter party;

  setUp(() {
    f = Fixture();
    party = f.r.defineFact(
      FactDescriptor(
        'porch.party',
        type: const RecordType({
          'from': Field(TextType()),
          'visitors': Field(IntType(min: 0)),
        }),
      ),
      by: const Principal('plugin', 'gate'),
    );
  });
  tearDown(() => f.r.dispose());

  group('facts', () {
    test('a fact kept is found by its id; one no longer kept is not', () async {
      final r = Registry(recentPerFact: 2);
      addTearDown(r.dispose);
      final said = r.defineFact(
        FactDescriptor('deck.said', type: const IntType()),
        by: const Principal('deck'),
      );
      for (final (i, id) in ['s1', 's2', 's3'].indexed) {
        said.emit(i, id: id);
      }
      await pumpEventQueue();
      expect(r.recentFact('s1'), isNull, reason: 'past recentPerFact');
      expect(r.recentFact('s3')?.payload, 2);
      expect(r.recentFact('s2')?.payload, 1);
    });

    test('a repeated id is dropped', () async {
      final seen = <FactMessage>[];
      f.r.facts(fact: 'porch.party').listen(seen.add);
      expect(party.emit({'from': 'a', 'visitors': 3}, id: 'r1'), isTrue);
      expect(party.emit({'from': 'a', 'visitors': 3}, id: 'r1'), isFalse);
      await pumpEventQueue();
      expect(seen.single.id, 'r1');
      expect(seen.single.cause.by, const Principal('plugin', 'gate'));
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
      expect(() => party.emit({'from': 'a'}), throwsA(isA<TypeMismatch>()));
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
        f.locked.set(true);
        party.emit({'from': 'a', 'visitors': 1});
      });
      await pumpEventQueue();
      final t = ticks.single;
      expect(t.changes.single.seq, t.from);
      expect(t.facts.single.seq, t.to);
    });
  });

  group('feed', () {
    test('starts with a snapshot, then live ticks', () async {
      f.locked.set(true);
      final items = <FeedItem>[];
      final sub = f.r.feed().listen(items.add);
      await pumpEventQueue();
      f.focus.set('main');
      await pumpEventQueue();
      final snap = items.first as Snapshot;
      expect(snap.states['door.locked'], {null: true});
      expect(snap.factsLost, isFalse);
      expect(items.last, isA<Tick>());
      await sub.cancel();
    });

    test('resumes after a retained seq, without gaps or repeats', () async {
      f.locked.set(true);
      final mark = f.r.seq;
      f.focus.set('main');
      party.emit({'from': 'a', 'visitors': 1});
      final items = <FeedItem>[];
      final sub = f.r.feed(epoch: f.r.epoch, since: mark).listen(items.add);
      await pumpEventQueue();
      f.locked.set(false);
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

    test('a big value rewritten is not kept in every version', () async {
      final r = Registry(retainBytes: 10000);
      final w = r.defineState(
        StateDescriptor('x.doc', type: const AnyType()),
        by: owner,
      );
      for (var i = 0; i < 5; i++) {
        w.set({'v': i, 'text': 'x' * 4000});
      }
      final old = await r.feed(epoch: r.epoch, since: 1).first;
      expect(old, isA<Snapshot>(), reason: 'the oldest ticks were dropped');
      final recent = r.feed(epoch: r.epoch, since: r.seq - 1);
      final items = <FeedItem>[];
      final sub = recent.listen(items.add);
      await pumpEventQueue();
      expect(items.single, isA<Tick>(), reason: 'the last one is kept');
      await sub.cancel();
    });

    test('the newest is kept however big', () async {
      final r = Registry(retainBytes: 100);
      final w = r.defineState(
        StateDescriptor('x.doc', type: const AnyType()),
        by: owner,
      );
      final f = r.defineFact(
        FactDescriptor('x.big', type: const AnyType()),
        by: owner,
      );
      w.set({'text': 'x' * 4000});
      w.set({'text': 'y' * 4000});
      f.emit({'text': 'z' * 4000});
      expect(r.recent('x.big'), hasLength(1));
      final feed = r.feed(epoch: r.epoch, since: r.seq - 1);
      final items = <FeedItem>[];
      final sub = feed.listen(items.add);
      await pumpEventQueue();
      expect(items.single, isA<Tick>());
      await sub.cancel();
    });
  });
}
