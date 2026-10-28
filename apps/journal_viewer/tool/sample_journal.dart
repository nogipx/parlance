/// Writes a sample journal to look at: a studio, viewers' chat lines, a
/// plugin that answers them, a press at the desk, some of it refused or
/// failed, with real time between.
///
/// Run: `fvm dart run tool/sample_journal.dart [file]` (journal-sample.jsonl).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:parlance/participant.dart';
import 'package:parlance/registry.dart';

Future<void> main(List<String> args) async {
  final out = File(args.isEmpty ? 'journal-sample.jsonl' : args.first);
  final sink = out.openWrite();
  final r = Registry(overriders: {'user'});
  final sub = r.journal.listen((e) => sink.writeln(jsonEncode(e.toJson())));
  final rnd = Random(7);
  Future<void> wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

  const studio = Principal('studio');
  final p = r.participant(
    studio,
    vocabularies: [
      const WordSet.open('chat'),
      const WordSet.open('replay'),
      const WordSet.open('screen'),
      const WordSet.open('stream'),
    ],
  );
  final line = p.defineFact(
    FactDescriptor(
      'chat.line',
      type: const ObjectType({'text': Field(TextType())}),
    ),
  );
  final saved = p.defineState(
    StateDescriptor('replay.last', type: const TextType()),
  );
  final covered = p.defineState(
    StateDescriptor('screen.covered', type: const BoolType()),
  );
  p.defineCommand(
    CommandDescriptor(
      'chat.say',
      params: const ObjectType({'text': Field(TextType())}),
      callers: Callers.only(['viewer']),
    ),
    (c) => line.emit({'text': c.params['text']}, cause: c.causeFor(studio)),
  );
  var n = 0;
  var cover = false;
  p.defineCommand(
    CommandDescriptor(
      'replay.save',
      params: const ObjectType({'seconds': Field(IntType())}),
      callers: Callers.only(['plugin', 'user']),
    ),
    (c) async {
      await wait(120 + rnd.nextInt(400));
      if (++n % 4 == 0) throw StateError('the encoder is not running');
      saved.set('clip-$n.mp4', cause: c.causeFor(studio));
      return null;
    },
  );
  p.defineCommand(
    CommandDescriptor(
      'screen.cover.toggle',
      callers: Callers.only(['user', 'plugin']),
    ),
    (c) async {
      await wait(30);
      cover = !cover;
      covered.set(cover, cause: c.causeFor(studio));
    },
  );
  p.defineCommand(
    CommandDescriptor('stream.end', callers: Callers.only(['user'])),
    (_) {},
  );

  const basics = Principal('plugin', 'tephra_basics');
  final plugin = r.participant(basics);
  plugin.facts('chat.line').listen((f) async {
    final text = '${(f.payload as Map)['text']}';
    if (!text.startsWith('!clip')) return;
    final cause = Cause(basics, parent: f.id);
    await plugin.call('replay.save', {'seconds': 90}, cause: cause);
    if (text.contains('end')) {
      await plugin.call('stream.end', {}, cause: cause);
    }
  });

  final viewers = ['twitch.7', 'twitch.42', 'youtube.UCx9', 'twitch.1337'];
  final user = r.participant(const Principal('user', 'local'));
  for (var i = 0; i < 14; i++) {
    final who = r.participant(Principal('viewer', viewers[i % viewers.length]));
    final text = switch (i % 5) {
      0 || 3 => '!clip',
      4 => '!clip and end it',
      _ => 'hello ${i + 1}',
    };
    await who.call('chat.say', {'text': text}, id: 'irc:$i');
    if (i % 6 == 2) {
      await user.call('screen.cover.toggle', {}, id: 'desk:$i');
    }
    await wait(300 + rnd.nextInt(1500));
  }
  await wait(800);
  await sub.cancel();
  await r.dispose();
  await sink.close();
  stdout.writeln('wrote ${out.path}');
}
