import 'package:parlance/app.dart';
import 'package:parlance/tools.dart';
import 'package:parlance_links/parlance_links.dart';
import 'package:test/test.dart';

void main() {
  test(
    'a link hears one provider and invokes the explicitly selected receiver',
    () async {
      final host = Host();
      addTearDown(host.dispose);
      final left = host
          .participant(
            const Principal('module', 'left'),
            vocabularies: [const WordSet.open('counter')],
          )
          .raw;
      final right = host
          .participant(
            const Principal('module', 'right'),
            vocabularies: [const WordSet.open('counter')],
          )
          .raw;
      final a = left.defineFact(
        FactDescriptor('counter.changed', type: const AnyType()),
      );
      final b = right.defineFact(
        FactDescriptor('counter.changed', type: const AnyType()),
      );
      final called = <String>[];
      left.defineCommand(
        CommandDescriptor('counter.note', callers: Callers.anyone),
        (_) => called.add('left'),
      );
      right.defineCommand(
        CommandDescriptor('counter.note', callers: Callers.anyone),
        (c) {
          expect(c.by, const Principal('plugin', 'rules'));
          expect(c.cause.origin!.word, 'module/left/counter.changed');
          called.add('right');
        },
      );
      final participant = host.participant(
        const Principal('plugin', 'rules'),
        vocabularies: [const WordSet.open('rules')],
      );
      final links = Links(participant, vocabulary: 'rules');
      addTearDown(links.dispose);
      await links.load([
        {
          'id': 'forward',
          'when': [
            {'fact': 'module/left/counter.changed'},
          ],
          'do': [
            {'call': 'module/right/counter.note'},
          ],
        },
      ]);
      expect(links.problems, isEmpty);
      b.say({});
      await participant.settle();
      expect(called, isEmpty);
      a.say({});
      await participant.settle();
      expect(called, ['right']);
    },
  );
}
