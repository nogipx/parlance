import 'dart:async';

import 'package:parlance/app.dart';
import 'package:parlance/testing.dart';
import 'package:parlance/tools.dart' show OwnerParticipant, RawAccess;
import 'package:test/test.dart';

part 'where_test.g.dart';

/// The contract tests' promises (`contract_test.dart`), held the
/// same wherever each side runs: every test runs four times, the owner in
/// the host's process or across a connection, and the part that uses its
/// words in the host's process or across one. One expectation for all
/// four: where they differ, a promise leaks.
@Vocabulary('deck')
abstract class Deck {
  @StateWord('volume')
  @Range(min: 0, max: 10)
  int get volume;

  @StateWord('level', keyOf: 'channel')
  int get level;

  @CommandWord('turn', callers: Callers.anyone)
  int turn({@Range(min: 0, max: 10) required int to});

  @CommandWord('play', callers: Callers.anyone)
  String play({required String track});

  @CommandWord('slow', callers: Callers.anyone)
  Future<void> slow();

  @CommandWord(
    'late',
    callers: Callers.anyone,
    deadline: Duration(milliseconds: 50),
  )
  Future<void> late();

  @CommandWord('fail', callers: Callers.anyone)
  void fail();

  @CommandWord('bump', callers: Callers.anyone)
  void bump();

  @CommandWord('ring', callers: Callers.anyone)
  void ring({required String id});

  @QueryWord('find', askers: Callers.anyone)
  String find({required String text});

  @FactWord('played')
  void played({required String track});
}

final class DeckOwner extends DeckOwnerBase {
  DeckOwner() {
    choices(name: 'channel', list: () => [Choice('a'), Choice('b')]);
    guard(
      id: 'gentle',
      word: DeckCommand.turn,
      check: (call) => call.params.to > 8 ? 'too loud' : null,
    );
  }

  /// Who each call came on behalf of, as the handler saw it.
  final List<Principal?> by = [];

  /// The handler's token of each call it served.
  final List<CancellationToken?> expiredSeen = [];
  final Completer<void> release = Completer();
  var ran = 0;

  @override
  int turn({required int to}) {
    ran++;
    by.add(OwnerTools(this).by);
    volume.set(to);
    return to;
  }

  @override
  String play({required String track}) {
    played.say(track: track);
    return 'playing $track';
  }

  @override
  Future<void> slow() async {
    ran++;
    expiredSeen.add(expired);
    await release.future;
  }

  @override
  Future<void> late() => release.future;

  @override
  void fail() => throw StateError('broken');

  @override
  void bump() => batch(() {
    volume.set(9);
    level.set('a', 9);
    throw StateError('no');
  });

  @override
  void ring({required String id}) => once(
    id: id,
    say: () => played.say(track: 'ring'),
  );

  @override
  String find({required String text}) => 'found $text';
}

const user = Principal('user');
const deckOwner = Principal('deck');

void main() {
  for (final ownerAcross in [false, true]) {
    for (final userAcross in [false, true]) {
      final where =
          'owner ${ownerAcross ? 'across' : 'here'}, '
          'user ${userAcross ? 'across' : 'here'}';
      group(where, () {
        late TestHost host;
        late DeckOwner deck;
        late IParticipant owner;
        late IParticipant you;
        late IDeckClient client;

        /// The participants a test ended: not asked to settle.
        final gone = <IParticipant>{};

        Future<void> settle() async {
          for (final p in [owner, you]) {
            if (!gone.contains(p)) await p.settle();
          }
          await host.settle();
        }

        /// Ends [p], as its `main` would: a guest's awaited.
        Future<void> end(IParticipant p) async {
          gone.add(p);
          if (p case final IRemoteParticipant r) {
            await r.dispose();
          } else {
            p.dispose();
          }
        }

        setUp(() async {
          gone.clear();
          host = TestHost();
          deck = DeckOwner();
          if (ownerAcross) {
            final p = await host.join(deckOwner, vocabularies: [deckWords]);
            await p.attach([deck]);
            owner = p;
          } else {
            owner = host.participant(deckOwner, owners: [deck]);
          }
          you = userAcross ? await host.join(user) : host.participant(user);
          client = IDeckClient(you);
          await settle();
        });
        tearDown(() async {
          if (!deck.release.isCompleted) deck.release.complete();
          await host.dispose();
        });

        group('reading', () {
          test('a state listened to reads what its owner set', () async {
            final seen = <int?>[];
            final sub = client.volume.changes.listen(seen.add);
            deck.volume.set(3);
            await settle();
            expect(client.volume.value, 3);
            expect(seen.last, 3);
            await sub.cancel();
          });

          test('a keyed state reads by key, whole, and its keys', () async {
            final sub = client.level.changes.listen((_) {});
            deck.level
              ..set('a', 1)
              ..set('b', 2);
            await settle();
            expect(client.level.of('a'), 1);
            expect(client.level.all, {'a': 1, 'b': 2});
            expect(client.level.keys, unorderedEquals(['a', 'b']));
            await sub.cancel();
          });

          test(
            'a state read without listening reads what its owner set',
            () async {
              deck.volume.set(4);
              await settle();
              expect(client.volume.value, 4);
            },
          );

          test('a fact listened to is heard once said', () async {
            final heard = <String>[];
            final sub = client.played.payloads
                .map((p) => p.track)
                .listen(heard.add);
            await settle();
            await client.play(track: 'x');
            await settle();
            expect(heard, ['x']);
            await sub.cancel();
          });

          test('the facts said before are there to read back', () async {
            await client.play(track: 'one');
            await client.play(track: 'two');
            await settle();
            final recent = await client.played.recent(5);
            expect([for (final f in recent) f.payload.track], ['one', 'two']);
          });
        });

        group('calling', () {
          test('a read after a call reads what it wrote', () async {
            final sub = client.volume.changes.listen((_) {});
            await settle();
            expect(await client.turn(to: 6), 6);
            expect(client.volume.value, 6);
            await sub.cancel();
          });

          test(
            'a command answers its value; its handler sees who called',
            () async {
              expect(await client.play(track: 'y'), 'playing y');
              await client.turn(to: 2);
              expect(deck.by.last, user);
            },
          );

          test('a guard that says no refuses it, denied, by its id', () async {
            await expectLater(
              client.turn(to: 9),
              throwsA(
                isA<CallNotDone>().having(
                  (e) => e.result,
                  'result',
                  isA<CallRefused>()
                      .having((r) => r.code, 'code', Refusal.denied)
                      .having((r) => r.guard, 'guard', contains('gentle')),
                ),
              ),
            );
            expect(deck.ran, 0);
          });

          test(
            'params out of their bounds are refused before the handler',
            () async {
              await expectLater(
                client.turn(to: 11),
                throwsA(isA<CallNotDone>()),
              );
              expect(deck.ran, 0);
            },
          );

          test('a handler that throws ends failed', () async {
            await expectLater(
              client.fail(),
              throwsA(
                isA<CallNotDone>().having(
                  (e) => e.result,
                  'result',
                  isA<CallFailed>(),
                ),
              ),
            );
          });

          test('no answer within the deadline ends timedOut', () async {
            await expectLater(
              client.late(),
              throwsA(
                isA<CallNotDone>().having(
                  (e) => e.result,
                  'result',
                  isA<CallTimedOut>(),
                ),
              ),
            );
          });

          test(
            'a call cancelled ends cancelled, and its handler is told',
            () async {
              final stop = CancellationToken();
              final r = client.slow(cancel: stop);
              await settle();
              expect(deck.ran, 1);
              stop.cancel();
              await expectLater(
                r,
                throwsA(
                  isA<CallNotDone>().having(
                    (e) => e.result,
                    'result',
                    isA<CallCancelled>(),
                  ),
                ),
              );
              await settle();
              expect(deck.expiredSeen.single?.isCancelled, isTrue);
            },
          );

          test('a retry with the same id runs once', () async {
            final turn = GeneratedWords(you).command(DeckCommand.turn);
            final a = await turn.call((to: 3), id: 'same');
            final b = await turn.call((to: 3), id: 'same');
            expect(a.ok, isTrue);
            expect(b.ok, isTrue);
            expect(deck.ran, 1);
          });

          test('a query answers', () async {
            expect(await client.find(text: 'z'), 'found z');
          });
        });

        group('owning', () {
          test(
            'a batch that throws writes nothing, its own copy too',
            () async {
              final sub = client.volume.changes.listen((_) {});
              await client.turn(to: 1);
              await expectLater(client.bump(), throwsA(isA<CallNotDone>()));
              await settle();
              expect(client.volume.value, 1);
              expect(deck.volume.value, 1);
              expect(deck.level.all, isEmpty);
              await sub.cancel();
            },
          );

          test('a fact said again under the same id is heard once', () async {
            final heard = <String>[];
            final sub = client.played.payloads
                .map((p) => p.track)
                .listen(heard.add);
            await settle();
            await client.ring(id: 'r1');
            await client.ring(id: 'r1');
            await settle();
            expect(heard, ['ring']);
            await sub.cancel();
          });

          test('a set out of its bounds is refused, and the owner keeps '
              'what it had', () async {
            deck.volume.set(2);
            expect(() => deck.volume.set(50), throwsA(anything));
            expect(deck.volume.value, 2);
          });
        });

        group('lifetime', () {
          test('words go with their participant: the user sees them '
              'missing, and a call is refused unknown', () async {
            await end(owner);
            await settle();
            expect(client.status(DeckCommand.play), isA<WordMissing>());
            await expectLater(
              client.play(track: 'gone'),
              throwsA(
                isA<CallNotDone>().having(
                  (e) => e.result,
                  'result',
                  isA<CallRefused>().having(
                    (r) => r.code,
                    'code',
                    Refusal.unknownCommand,
                  ),
                ),
              ),
            );
          });

          test(
            'an owner gone writes nowhere, and says it was withdrawn',
            () async {
              final sub = client.volume.changes.listen((_) {});
              await client.turn(to: 5);
              await end(owner);
              deck.volume.set(7);
              await settle();
              expect(
                host
                    .participant(const Principal('observer'))
                    .raw
                    .read('deck.volume'),
                isNull,
              );
              expect(
                () => OwnerParticipant(deck).participant,
                throwsStateError,
              );
              await sub.cancel();
            },
          );

          test('a participant gone refuses what it is asked', () async {
            await end(you);
            await expectLater(
              Future.sync(() => you.raw.call('deck.play', {})),
              throwsStateError,
            );
          });
        });
      });
    }
  }
}
