import 'dart:async';

import 'package:clock/clock.dart';
import 'package:parlance/app.dart';
import 'package:test/test.dart';
import 'package:parlance/tools.dart' show OwnerParticipant, StateWordOf;
import 'package:parlance/testing.dart';

part 'owner_tools_more_test.g.dart';

/// What an owner says with the tools beside its words (SPEC §19): a guard
/// of its own command by its params, the time by the registry's clock,
/// a word named at run time, and a command's status that follows what it
/// heard, with no one telling the registry so.
@Vocabulary('dial')
abstract class Dial {
  @CommandWord('set', callers: Callers.anyone, whyNot: true)
  void set({required int to});
}

/// No words: a rule of the whole participant.
@Vocabulary('rules')
abstract class Rules {}

@Vocabulary('bell')
abstract class Bell {
  @FactWord('rang')
  void rang({required String who});
}

/// Lamps of bulbs: which are lit, by bulb; a bulb dropped goes of them by
/// itself, as a choice and as a key.
@Vocabulary('lamps')
abstract class Lamps {
  @StateWord('lit', keyOf: 'bulb')
  bool get lit;

  @CommandWord('drop', callers: Callers.anyone)
  void drop({@ChoiceOf('bulb') required String bulb});
}

final class _Dial extends DialOwnerBase {
  _Dial(Stream<bool> power) {
    guard(
      id: 'gentle',
      word: DialCommand.set,
      check: (call) => call.params.to > 10 && call.by.kind != 'admin'
          ? 'too far for ${call.by}'
          : null,
    );
    listen(on: power, onData: (on) => this.on = on);
    whenAttached(
      (p) => GeneratedWords(p)
          .state(StateWordOf<int>('dial.$serial', const PlainShape(IntType())))
          .define()
          .set(7),
    );
  }

  final String serial = 'x1';
  var on = true;
  int? at;

  @override
  void set({required int to}) => at = to;

  @override
  String? whyNotSet() => on ? null : 'it is off';
}

/// An owner of rules alone: no words of its own.
final class _NoAgents extends RulesOwnerBase {
  _NoAgents() {
    guardAll(
      id: 'no-agents',
      check: (call) =>
          call.by.kind == 'agent' ? 'no agent calls ${call.command}' : null,
    );
  }
}

final class _Bell extends BellOwnerBase {
  /// A ring from outside, which may come twice.
  bool ring(String id, String who) => once(
    id: id,
    say: () => rang.say(who: who),
  );
}

final class _Lamps extends LampsOwnerBase {
  _Lamps({bool listed = true}) {
    if (listed) {
      choices(
        name: LampsChoices.bulb,
        list: () => [for (final b in bulbs) Choice(b)],
      );
    }
    follow(
      pull: () {
        for (final b in bulbs) {
          lit.set(b, true);
        }
      },
    );
  }

  final List<String> bulbs = ['a', 'b'];

  @override
  void drop({required String bulb}) => bulbs.remove(bulb);
}

void main() {
  test('a choice that went goes of the keyed states by its kind, with '
      'no one removing it', () async {
    final r = Host();
    addTearDown(r.dispose);
    final lamps = _Lamps();
    r.participant(const Principal('lamps'), owners: [lamps]);
    final ann = r.participant(const Principal('user', 'ann'));
    expect(GeneratedWords(ann).keyedOf(LampsState.lit).keys, {'a', 'b'});

    expect(
      await GeneratedWords(ann).command(LampsCommand.drop).call((bulb: 'b')),
      isA<CallDone<void>>(),
    );
    await ann.settle();
    expect(GeneratedWords(ann).keyedOf(LampsState.lit).keys, {'a'});
    expect(lamps.lit.keys, ['a']);
    final gone = await GeneratedWords(
      ann,
    ).command(LampsCommand.drop).call((bulb: 'b'));
    expect(gone.why, contains('no bulb b'));
  });

  test('a ref to choices no one gives says so', () async {
    final r = Host();
    addTearDown(r.dispose);
    r.participant(const Principal('lamps'), owners: [_Lamps(listed: false)]);
    final ann = r.participant(const Principal('user', 'ann'));
    final r1 = await GeneratedWords(
      ann,
    ).command(LampsCommand.drop).call((bulb: 'a'));
    expect(r1.why, contains("choices(name: 'bulb', list: ...)"));
  });

  test('a fact said once by its id is said once, however often it '
      'comes', () async {
    final r = Host();
    addTearDown(r.dispose);
    final bell = _Bell();
    r.participant(const Principal('bell'), owners: [bell]);
    final heard = <String>[];
    final ann = r.participant(const Principal('user', 'ann'));
    GeneratedWords(
      ann,
    ).factOf(BellFact.rang).facts.listen((f) => heard.add(f.payload.who));
    expect(bell.ring('e1', 'bob'), isTrue);
    expect(bell.ring('e1', 'bob'), isFalse);
    expect(bell.ring('e2', 'cat'), isTrue);
    await ann.settle();
    expect(heard, ['bob', 'cat']);
  });

  test('a guard of its own command judges the params and who calls', () async {
    final r = Host();
    addTearDown(r.dispose);
    final power = Stream<bool>.empty();
    r.participant(const Principal('dial'), owners: [_Dial(power)]);
    final ann = r.participant(const Principal('user', 'ann'));
    final admin = r.participant(const Principal('admin'));

    expect(
      await GeneratedWords(ann).command(DialCommand.set).call((to: 3)),
      isA<CallDone<void>>(),
    );
    final far = await GeneratedWords(
      ann,
    ).command(DialCommand.set).call((to: 30));
    expect(far, isA<CallRefused>());
    expect(far.why, contains('too far for user/ann'));
    expect(
      await GeneratedWords(admin).command(DialCommand.set).call((to: 30)),
      isA<CallDone<void>>(),
    );
  });

  test('a guard of all the commands of its participant judges those of '
      'the owners beside it too, here and on a guest', () async {
    for (final across in [false, true]) {
      final host = TestHost();
      addTearDown(host.dispose);
      final owners = [_Dial(const Stream.empty()), _NoAgents()];
      if (across) {
        final dial = await host.join(
          const Principal('dial'),
          vocabularies: [dialWords, rulesWords],
        );
        await dial.attach(owners);
      } else {
        host.participant(const Principal('dial'), owners: owners);
      }
      await host.settle();
      final agent = host.participant(const Principal('agent', 'a'));
      final ann = host.participant(const Principal('user', 'ann'));
      final refused = await GeneratedWords(
        agent,
      ).command(DialCommand.set).call((to: 3));
      expect(refused, isA<CallRefused>(), reason: 'across: $across');
      expect(refused.why, contains('no agent calls dial.set'));
      expect(
        await GeneratedWords(ann).command(DialCommand.set).call((to: 3)),
        isA<CallDone<void>>(),
      );
    }
  });

  test('what it heard moves its command\'s status, unasked', () async {
    final r = Host();
    addTearDown(r.dispose);
    final power = StreamController<bool>();
    r.participant(const Principal('dial'), owners: [_Dial(power.stream)]);
    final ann = r.participant(const Principal('user', 'ann'));
    final seen = <WordStatus>[];
    final sub = GeneratedWords(
      ann,
    ).statusChanges(DialCommand.set).listen(seen.add);
    await ann.settle();

    power.add(false);
    await ann.settle();
    expect(GeneratedWords(ann).status(DialCommand.set), isA<WordUnavailable>());
    power.add(true);
    await ann.settle();
    expect(GeneratedWords(ann).status(DialCommand.set), isA<WordReady>());
    await sub.cancel();
    expect(seen.whereType<WordUnavailable>(), hasLength(1));
  });

  test('a word named at run time is defined as any other', () async {
    final r = Host();
    addTearDown(r.dispose);
    final p = r.participant(
      const Principal('dial'),
      owners: [_Dial(const Stream.empty())],
    );
    expect(
      GeneratedWords(
        p,
      ).stateOf(const StateWordOf<int>('dial.x1', PlainShape(IntType()))).value,
      7,
    );
  });

  test('now is the registry\'s clock once attached, the world\'s before', () {
    final then = DateTime.utc(2030, 1, 2);
    final r = Host(clock: Clock.fixed(then));
    addTearDown(r.dispose);
    final dial = _Dial(const Stream.empty());
    expect(dial.now, isNot(then));
    r.participant(const Principal('dial'), owners: [dial]);
    expect(dial.now, then);
  });
}
