import 'dart:async';

import 'package:parlance/app.dart';
import 'package:parlance/testing.dart';
import 'package:parlance/tools.dart';
import 'package:parlance/src/registry/registry.dart' show RawRegistry;
import 'package:parlance/src/remote/contract.dart'
    show ParlanceContractPeerCaller, WireDefine;
import 'package:rpc_dart/rpc_dart.dart';
import 'package:test/test.dart';

part 'target_test.g.dart';

const work = Principal('module', 'work');
const personal = Principal('module', 'personal');
const bare = Principal('module');
const ann = Principal('user', 'ann');

@Vocabulary('counter')
abstract class Counter {
  @StateWord('value')
  int get value;

  @StateWord('item', keyOf: 'item')
  int get item;

  @StateWord('caller')
  String get caller;

  @CommandWord('add')
  Future<int> add({required int amount});

  @QueryWord('current')
  int current();

  @FactWord('changed')
  void changed({required int value});

  @ServerStreamWord('samples')
  Stream<int> samples();

  @ClientStreamWord('sum')
  Future<int> sum(Stream<int> values);

  @BidiStreamWord('scale')
  Stream<int> scale(Stream<int> values);
}

final class Counting extends CounterOwnerBase {
  Counting(this.factor, {bool nonnegative = false}) {
    value.set(factor);
    item.set('same-id', factor);
    if (nonnegative) {
      guard(
        id: 'nonnegative',
        word: CounterCommand.add,
        check: (c) => c.params.amount < 0 ? 'negative amount' : null,
      );
    }
  }

  final int factor;

  bool announce(String id, int next) => once(
    id: id,
    say: () => changed.say(value: next),
  );

  @override
  Future<int> add({required int amount}) async {
    final initialCaller = by;
    await Future<void>.delayed(Duration.zero);
    if (by != initialCaller) throw StateError('caller lost across await');
    caller.set(by!.selector);
    final next = value.value! + amount;
    value.set(next);
    item.set('same-id', next);
    changed.say(value: next);
    return next;
  }

  @override
  int current() => value.value!;

  @override
  Stream<int> samples() => Stream.fromIterable([factor, factor + 1]);

  @override
  Future<int> sum(Stream<int> values) async =>
      factor + await values.fold(0, (a, b) => a + b);

  @override
  Stream<int> scale(Stream<int> values) => values.map((v) => v * factor);
}

@Vocabulary('bridge')
abstract class Bridge {
  @CommandWord('forward')
  Future<int> forward({required int amount});
}

final class Forwarding extends BridgeOwnerBase {
  Forwarding(Principal target) {
    counter = ICounterClient.of(owner: this, target: target);
  }
  late final ICounterClient counter;
  @override
  Future<int> forward({required int amount}) => counter.add(amount: amount);
}

void main() {
  for (final ownerAcross in [false, true]) {
    for (final consumerAcross in [false, true]) {
      group('owner=$ownerAcross consumer=$consumerAcross', () {
        late TestHost host;
        late IParticipant user;
        setUp(() async {
          host = TestHost();
          user = consumerAcross ? await host.join(ann) : host.participant(ann);
        });
        tearDown(() => host.dispose());

        Future<IParticipant> publish(
          Principal who,
          Counting owner, {
          Callers callers = Callers.anyone,
        }) async {
          if (ownerAcross) {
            final p = await host.join(
              who,
              vocabularies: [CounterVocabulary.definition],
              access: WordAccess(callers: callers),
            );
            await p.attach([owner]);
            return p;
          }
          return host.participant(
            who,
            owners: [owner],
            access: WordAccess(callers: callers),
          );
        }

        test(
          'same vocabulary, keys, facts and all stream kinds stay independent',
          () async {
            await publish(work, Counting(2));
            await publish(personal, Counting(10));
            await publish(bare, Counting(30));
            final a = ICounterClient(participant: user, target: work);
            final b = ICounterClient(participant: user, target: personal);
            final c = ICounterClient(participant: user, target: bare);
            final heardA = <int>[], heardB = <int>[];
            final sa = a.changed.payloads.listen((e) => heardA.add(e.value));
            final sb = b.changed.payloads.listen((e) => heardB.add(e.value));
            await host.settle();
            expect(await a.add(amount: 3), 5);
            expect(await b.add(amount: 7), 17);
            await host.settle();
            expect(a.value.value, 5);
            expect(b.value.value, 17);
            expect(c.value.value, 30);
            expect(a.item.of('same-id'), 5);
            expect(b.item.of('same-id'), 17);
            expect(await a.current(), 5);
            expect(heardA, [5]);
            expect(heardB, [17]);
            expect(await a.samples().toList(), [2, 3]);
            expect(await b.samples().toList(), [10, 11]);
            expect(await a.sum(Stream.fromIterable([1, 2])), 5);
            expect(await b.sum(Stream.fromIterable([1, 2])), 13);
            expect(await a.scale(Stream.fromIterable([1, 2])).toList(), [2, 4]);
            expect(await b.scale(Stream.fromIterable([1, 2])).toList(), [
              10,
              20,
            ]);
            expect(a.caller.value, ann.selector);
            expect(b.caller.value, ann.selector);
            await sa.cancel();
            await sb.cancel();
          },
        );

        test(
          'call ids belong to the caller instance and retries keep their receiver',
          () async {
            await publish(work, Counting(1));
            const bob = Principal('user', 'bob');
            final other = consumerAcross
                ? await host.join(bob)
                : host.participant(bob);
            const address = 'module/work/counter.add';
            final first = await user.raw.call(address, {
              'amount': 1,
            }, id: 'same-id');
            final second = await other.raw.call(address, {
              'amount': 1,
            }, id: 'same-id');
            expect(
              first,
              isA<CallDone<Object?>>().having((r) => r.value, 'value', 2),
            );
            expect(
              second,
              isA<CallDone<Object?>>().having((r) => r.value, 'value', 3),
            );
            expect(
              await user.raw.call(address, {'amount': 1}, id: 'same-id'),
              isA<CallDone<Object?>>().having((r) => r.value, 'value', 2),
            );
            expect(
              await ICounterClient(participant: user, target: work).current(),
              3,
            );
          },
        );

        test(
          'explicit fact ids are deduplicated only within their full address',
          () async {
            final left = Counting(1), right = Counting(8);
            await publish(work, left);
            await publish(personal, right);
            final a = ICounterClient(participant: user, target: work);
            final b = ICounterClient(participant: user, target: personal);
            final fa = <Fact<CounterChanged>>[], fb = <Fact<CounterChanged>>[];
            final sa = a.changed.facts.listen(fa.add);
            final sb = b.changed.facts.listen(fb.add);
            await host.settle();
            left.announce('same-id', 11);
            right.announce('same-id', 22);
            left.announce('same-id', 33);
            await host.settle();
            expect(fa.map((f) => f.payload.value), [11]);
            expect(fb.map((f) => f.payload.value), [22]);
            expect(fa.single.id, isNot(fb.single.id));
            await sa.cancel();
            await sb.cancel();
          },
        );

        test(
          'bound clients and discovery follow exact target lifetimes',
          () async {
            final a = ICounterClient(participant: user, target: work);
            expect(a.status(CounterCommand.add), const WordMissing());
            final seen = <List<Principal>>[];
            final sub = user
                .targetChanges(word: CounterCommand.add.name)
                .listen((v) => seen.add(v.map((p) => p.principal).toList()));
            await host.settle();
            final p = await publish(work, Counting(1));
            await publish(personal, Counting(8));
            await host.settle();
            expect(a.status(CounterCommand.add), const WordReady());
            expect(
              (await user.targets(
                vocabulary: CounterVocabulary.name,
              )).map((p) => p.principal),
              [personal, work],
            );
            expect(seen.last, [personal, work]);
            p.dispose();
            await host.settle();
            expect(a.status(CounterCommand.add), const WordMissing());
            expect(seen.last, [personal]);
            expect(
              await ICounterClient(
                participant: user,
                target: personal,
              ).current(),
              8,
            );
            await publish(work, Counting(20));
            await host.settle();
            expect(await a.current(), 20);
            expect(seen.last, [personal, work]);
            await sub.cancel();
          },
        );

        test(
          'nested caller attribution and origin retain both receiver addresses',
          () async {
            await publish(work, Counting(1));
            const proxy = Principal('module', 'proxy');
            if (ownerAcross) {
              final p = await host.join(
                proxy,
                vocabularies: [BridgeVocabulary.definition],
                access: WordAccess(callers: Callers.anyone),
              );
              await p.attach([Forwarding(work)]);
            } else {
              host.participant(
                proxy,
                owners: [Forwarding(work)],
                access: WordAccess(callers: Callers.anyone),
              );
            }
            final counter = ICounterClient(participant: user, target: work);
            final client = IBridgeClient(participant: user, target: proxy);
            expect(await client.forward(amount: 3), 4);
            await host.settle();
            expect(counter.caller.value, 'module/proxy@bridge');
            final explanation = host.registry.explain(
              'module/work/counter.value',
            );
            expect(
              explanation.change!.cause.origin!.word,
              'module/proxy/bridge.forward',
            );
            expect(explanation.change!.cause.origin!.by, ann);
            expect(host.registry.mismatches, isEmpty);
          },
        );

        test('guards and access belong to the selected instance', () async {
          await publish(work, Counting(1, nonnegative: true));
          await publish(personal, Counting(8));
          await publish(bare, Counting(30), callers: Callers.only(['admin']));
          final a = ICounterClient(participant: user, target: work);
          final b = ICounterClient(participant: user, target: personal);
          final c = ICounterClient(participant: user, target: bare);
          expect(await b.add(amount: -1), 7);
          await expectLater(
            a.add(amount: -1),
            throwsA(
              isA<CallNotDone>().having(
                (e) => e.result,
                'result',
                isA<CallRefused>().having(
                  (r) => r.code,
                  'code',
                  Refusal.denied,
                ),
              ),
            ),
          );
          expect(c.status(CounterCommand.add), const WordNotPermitted());
          final targets = await user.targets(word: CounterCommand.add.name);
          expect(
            targets
                .singleWhere((p) => p.principal == bare)
                .vocabularies
                .single
                .words
                .single
                .status,
            const WordNotPermitted(),
          );
          expect(await a.current(), 1);
        });

        test(
          'name discovery groups actual words without merging vocabularies',
          () async {
            final first = await publish(work, Counting(2));
            await publish(personal, Counting(10));
            host.participant(
              work,
              owners: [Forwarding(personal)],
              access: const WordAccess(callers: Callers.anyone),
            );
            final extra = host
                .participant(
                  work,
                  vocabularies: const [
                    WordSet.open('counterfeit'),
                    WordSet.open('signal'),
                  ],
                )
                .raw;
            extra.defineState(
              StateDescriptor('counterfeit.value', type: const IntType()),
            );
            extra.defineFact(FactDescriptor('signal', type: const IntType()));
            host.registry.alias(
              'module/work/counter.old',
              'module/work/counter.value',
            );
            await host.settle();

            final all = await user.targets();
            final current = all.singleWhere((t) => t.principal == work);
            expect(current.vocabularies.map((v) => v.name), [
              'bridge',
              'counter',
              'counterfeit',
              'signal',
            ]);
            expect(() => current.vocabularies.clear(), throwsUnsupportedError);
            expect(
              () => current.vocabularies.first.words.clear(),
              throwsUnsupportedError,
            );
            expect(() => all.clear(), throwsUnsupportedError);

            final counters = await user.targets(
              vocabulary: CounterVocabulary.name,
            );
            expect(counters.map((t) => t.principal), [personal, work]);
            for (final target in counters) {
              expect(target.vocabularies.single.name, 'counter');
              expect(
                target.vocabularies.single.words.every(
                  (w) => w.address.word.startsWith('counter.'),
                ),
                isTrue,
              );
            }
            expect(
              counters.last.vocabularies.single.words.map(
                (w) => w.address.word,
              ),
              contains('counter.old'),
            );

            final named = await user.targets(word: CounterCommand.add.name);
            expect(named.map((t) => t.principal), [personal, work]);
            for (final target in named) {
              expect(
                target.vocabularies.single.words.single.address.word,
                'counter.add',
              );
            }
            final signal = await user.targets(
              vocabulary: 'signal',
              word: 'signal',
            );
            expect(signal.single.vocabularies.single.name, 'signal');
            expect(
              signal.single.vocabularies.single.words.single.address.word,
              'signal',
            );
            expect(
              await user.targets(vocabulary: 'counter', word: 'signal'),
              isEmpty,
            );
            expect(await user.targets(word: 'counter.missing'), isEmpty);

            final seen = <List<WordTarget>>[];
            final sub = user
                .targetChanges(vocabulary: CounterVocabulary.name)
                .listen(seen.add);
            await host.settle();
            first.dispose();
            await host.settle();
            expect(seen.last.map((t) => t.principal), [personal]);
            expect(
              (await user.targets()).any((t) => t.principal == work),
              isTrue,
            );
            await sub.cancel();
          },
        );
      });
    }
  }

  test('discovery requires valid portable names', () async {
    final host = TestHost();
    addTearDown(host.dispose);
    final user = host.participant(ann);
    await expectLater(
      user.targets(vocabulary: 'counter.value'),
      throwsArgumentError,
    );
    await expectLater(
      user.targets(word: 'module/work/counter.value'),
      throwsArgumentError,
    );
    await expectLater(user.targets(word: 'counter.v1'), throwsArgumentError);
    expect(() => user.targetChanges(vocabulary: ''), throwsArgumentError);
    expect(
      () => user.targetChanges(word: 'Counter.value'),
      throwsArgumentError,
    );
  });

  test(
    'duplicate exact vocabulary fails without disturbing either instance',
    () async {
      final host = TestHost();
      addTearDown(host.dispose);
      host.participant(
        work,
        owners: [Counting(1)],
        access: WordAccess(callers: Callers.anyone),
      );
      host.participant(
        personal,
        owners: [Counting(8)],
        access: WordAccess(callers: Callers.anyone),
      );
      expect(
        () => host.participant(
          work,
          owners: [Counting(99)],
          access: WordAccess(callers: Callers.anyone),
        ),
        throwsA(isA<NotPermitted>()),
      );
      final user = host.participant(ann);
      expect(
        await ICounterClient(participant: user, target: work).current(),
        1,
      );
      expect(
        await ICounterClient(participant: user, target: personal).current(),
        8,
      );
    },
  );

  test(
    'discovery tracks actual publication and availability, and cancellation stops it',
    () async {
      final host = TestHost();
      addTearDown(host.dispose);
      final owner = host
          .participant(work, vocabularies: [CounterVocabulary.definition])
          .raw;
      final user = host.participant(ann);
      expect(await user.targets(vocabulary: CounterVocabulary.name), isEmpty);
      final seen = <List<WordTarget>>[];
      final sub = user
          .targetChanges(word: CounterCommand.add.name)
          .listen(seen.add);
      await host.settle();
      String? unavailable;
      final definition = owner.defineCommand(
        CommandDescriptor(
          'counter.add',
          params: const RecordType({'amount': Field(IntType())}),
          returns: const IntType(),
          callers: Callers.anyone,
        ),
        (c) => c.params['amount'],
        whyNot: () => unavailable,
      );
      await host.settle();
      expect(
        seen.last.single.vocabularies.single.words.single.status,
        const WordReady(),
      );
      unavailable = 'offline';
      owner.whyNotChanged('module/work/counter.add');
      await host.settle();
      expect(
        seen.last.single.vocabularies.single.words.single.status,
        const WordUnavailable('offline'),
      );
      definition.dispose();
      await host.settle();
      expect(seen.last, isEmpty);
      await sub.cancel();
      final count = seen.length;
      owner.defineState(
        StateDescriptor('counter.value', type: const IntType()),
      );
      await host.settle();
      expect(seen, hasLength(count));
    },
  );

  test(
    'unscoped calls never select a target and a peer cannot publish another principal',
    () async {
      final host = TestHost();
      addTearDown(host.dispose);
      host.participant(
        work,
        owners: [Counting(1)],
        access: WordAccess(callers: Callers.anyone),
      );
      final peer = await host.join(
        personal,
        vocabularies: [CounterVocabulary.definition],
      );
      final caller = host.participant(ann).raw;
      expect(
        await caller.call('counter.add', {'amount': 1}),
        isA<CallRefused>().having(
          (r) => r.code,
          'code',
          Refusal.unknownCommand,
        ),
      );
      final wire = ParlanceContractPeerCaller(
        (peer as RemoteParticipant).endpoint,
        dataTransferMode: RpcDataTransferMode.codec,
      );
      await expectLater(
        wire.define(
          WireDefine(
            StateDescriptor(
              'module/work/counter.stolen',
              type: const IntType(),
            ).toJson(),
          ),
        ),
        throwsA(
          isA<RpcStatusException>().having(
            (e) => e.statusCode,
            'code',
            RpcStatus.permissionDenied,
          ),
        ),
      );
      expect(
        host.registry.stateDescriptor('module/work/counter.stolen'),
        isNull,
      );
      expect(
        await ICounterClient(participant: caller, target: work).current(),
        1,
      );
    },
  );

  for (final ownerAcross in [false, true]) {
    for (final consumerAcross in [false, true]) {
      test(
        'schema and aliases: owner=$ownerAcross consumer=$consumerAcross',
        () async {
          final host = TestHost();
          addTearDown(host.dispose);
          Future<IParticipant> publisher(Principal who) async => ownerAcross
              ? await host.join(who, vocabularies: [WordSet.open('counter')])
              : host.participant(who, vocabularies: [WordSet.open('counter')]);
          final a = (await publisher(work)).raw;
          final b = (await publisher(personal)).raw;
          final first = a.defineState(
            StateDescriptor('counter.value', type: const IntType()),
          )..set(1);
          b
              .defineState(
                StateDescriptor('counter.value', type: const IntType()),
              )
              .set(8);
          final user = consumerAcross
              ? await host.join(ann)
              : host.participant(ann);
          final ca = ICounterClient(participant: user, target: work);
          final cb = ICounterClient(participant: user, target: personal);
          host.registry.alias(
            'module/work/counter.old',
            'module/work/counter.value',
          );
          host.registry.alias(
            'module/personal/counter.old',
            'module/personal/counter.value',
          );
          await host.settle();
          const old = StateWordOf<int>('counter.old', PlainShape(IntType()));
          expect(
            GeneratedWords(participant: user, target: work).stateOf(old).value,
            1,
          );
          expect(
            GeneratedWords(
              participant: user,
              target: personal,
            ).stateOf(old).value,
            8,
          );
          expect(
            () => host.registry.alias(
              'module/work/counter.foreign',
              'module/personal/counter.value',
            ),
            throwsArgumentError,
          );
          first.dispose();
          a
              .defineState(
                StateDescriptor('counter.value', type: const TextType()),
              )
              .set('changed');
          await host.settle();
          expect(ca.status(CounterState.value), isA<WordMismatch>());
          expect(cb.status(CounterState.value), const WordReady());
          expect(host.registry.mismatches.map((m) => m.word).toSet(), {
            'module/work/counter.value',
          });
          final targets = await user.targets(word: CounterState.value.name);
          expect(
            targets
                .singleWhere((p) => p.principal == work)
                .vocabularies
                .single
                .words
                .single
                .status,
            const WordReady(),
          );
          expect(
            targets
                .singleWhere((p) => p.principal == personal)
                .vocabularies
                .single
                .words
                .single
                .status,
            const WordReady(),
          );
        },
      );
    }
  }

  test(
    'retry identity includes receiver and never retargets a completed call',
    () async {
      final host = TestHost();
      addTearDown(host.dispose);
      host.participant(
        work,
        owners: [Counting(1)],
        access: WordAccess(callers: Callers.anyone),
      );
      host.participant(
        personal,
        owners: [Counting(8)],
        access: WordAccess(callers: Callers.anyone),
      );
      final user = host.participant(ann).raw;
      final a = WordAddress(work, 'counter.add').toString();
      final b = WordAddress(personal, 'counter.add').toString();
      expect((await user.call(a, {'amount': 1}, id: 'retry')).ok, isTrue);
      expect((await user.call(a, {'amount': 1}, id: 'retry')).ok, isTrue);
      expect(
        await user.call(b, {'amount': 1}, id: 'retry'),
        isA<CallRefused>().having((r) => r.code, 'code', Refusal.idConflict),
      );
      expect(
        await ICounterClient(participant: user, target: work).current(),
        2,
      );
      expect(
        await ICounterClient(participant: user, target: personal).current(),
        8,
      );
    },
  );
}
