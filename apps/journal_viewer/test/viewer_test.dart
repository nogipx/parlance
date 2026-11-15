import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal_viewer/main.dart';
import 'package:journal_viewer/src/viewer.dart';
import 'package:parlance/app.dart' show Host;
import 'package:parlance/tools.dart';

const studio = Principal('studio');
const viewer = Principal('viewer', 'twitch.7');
const basics = Principal('plugin', 'basics');

/// A journal of two chat lines: each a call that says a fact, a plugin's
/// call in answer that writes, and one it may not make.
Future<String> journalLines() async {
  final host = Host();
  final r = host.registry;
  final lines = <String>[];
  final sub = r.journal.listen((e) => lines.add(jsonEncode(e.toJson())));
  final p = host
      .participant(
        studio,
        vocabularies: [const WordSet.open('chat'), const WordSet.open('clip')],
      )
      .raw;
  final line = p.defineFact(
    FactDescriptor('studio/chat.line', type: const TextType()),
  );
  final last = p.defineState(
    StateDescriptor('studio/clip.last', type: const TextType()),
  );
  p.defineCommand(
    CommandDescriptor('studio/chat.say', callers: Callers.only(['viewer'])),
    (c) => line.say('!clip', cause: c.causeFor(studio)),
  );
  var n = 0;
  p.defineCommand(
    CommandDescriptor('studio/clip.save', callers: Callers.only(['plugin'])),
    (c) => last.set('clip-${++n}', cause: c.causeFor(studio)),
  );
  p.defineCommand(
    CommandDescriptor('studio/clip.cover', callers: Callers.only(['user'])),
    (_) {},
  );
  final plugin = host.participant(basics).raw;
  plugin.facts('studio/chat.line').listen((f) async {
    await plugin.call(
      'studio/clip.save',
      {},
      cause: Cause(basics, parent: f.id),
    );
    await plugin.call(
      'studio/clip.cover',
      {},
      cause: Cause(basics, parent: f.id),
    );
  });
  for (final id in ['irc:1', 'irc:2']) {
    await host.participant(viewer).raw.call('studio/chat.say', {}, id: id);
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  await sub.cancel();
  await host.dispose();
  return '${lines.join('\n')}\n';
}

void main() {
  testWidgets('open a journal: its conversations, one as a tree, a message '
      'in it', (tester) async {
    final text = await tester.runAsync(journalLines);
    final v = Viewer()..load([(name: 'journal-2026-10-28.jsonl', text: text!)]);
    await tester.binding.setSurfaceSize(const Size(1500, 900));
    await tester.pumpWidget(JournalViewerApp(viewer: v));

    expect(find.text('studio/chat.say'), findsNWidgets(2));
    expect(find.textContaining('2 conversations'), findsOneWidget);

    await tester.tap(find.text('studio/chat.say').first);
    await tester.pump();
    expect(find.text('studio/chat.line'), findsOneWidget);
    expect(find.text('studio/clip.save'), findsOneWidget);
    expect(find.text('studio/clip.cover'), findsOneWidget);
    expect(find.text('studio/clip.last'), findsOneWidget);

    await tester.tap(find.text('studio/clip.cover'));
    await tester.pump();
    expect(find.text('refused'), findsOneWidget);
    expect(find.text('How it came about'), findsOneWidget);

    await tester.tap(find.byType(FilterChip));
    await tester.pump();
    expect(find.text('2 of 2'), findsOneWidget, reason: 'both had a refusal');
    await tester.binding.setSurfaceSize(null);
  });

  test('playback shows only what had happened by then, and jumps a quiet '
      'stretch', () async {
    final text = await journalLines();
    final v = Viewer()..load([(name: 'j.jsonl', text: text)]);
    final talks = v.all;
    expect(talks, hasLength(2));
    v.seek(talks.first.started);
    expect(v.conversations.map((c) => c.id), ['viewer/twitch.7#irc:1']);
    v.select(talks.first);
    expect(v.tree.single.children, isEmpty, reason: 'only the call so far');
    v.seek(v.last!);
    expect(v.conversations, hasLength(2));
    expect(v.tree.single.children.single.children, hasLength(2));

    v.seek(v.first!);
    v.play();
    v.speed = 1;
    v.advance(const Duration(milliseconds: 1));
    expect(v.playing, isTrue);
    v.advance(const Duration(hours: 1));
    expect(v.playing, isFalse, reason: 'it came to the end');
    expect(v.playhead, v.last);
    v.stop();
    expect(v.playhead, isNull);
  });

  test('a line that is no entry is skipped; files go in the order of '
      'their days', () async {
    final text = await journalLines();
    final lines = const LineSplitter().convert(text);
    final v = Viewer()
      ..load([
        (name: 'journal-2026-10-29.jsonl', text: lines.skip(3).join('\n')),
        (
          name: 'journal-2026-10-28.jsonl',
          text: '${lines.take(3).join('\n')}\n{"cut',
        ),
      ]);
    expect(v.files, ['journal-2026-10-28.jsonl', 'journal-2026-10-29.jsonl']);
    expect(v.entries, hasLength(lines.length));
  });
}
