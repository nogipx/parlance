import 'dart:io';

import 'package:parlance/participant.dart';
import 'package:parlance/registry.dart';
import 'package:parlance_journal/parlance_journal.dart';
import 'package:rpc_dart/logger.dart';
import 'package:test/test.dart';

const studio = Principal('studio');
const user = Principal('user', 'local');
const viewer = Principal('viewer', 'twitch.7');
const basics = Principal('plugin', 'basics');

/// A studio of a chat line, a clip saved in answer and a cover only the
/// user may set: what a journal of it keeps.
final class Studio {
  Studio({LogScope? log}) : r = Registry(log: log) {
    final p = r.participant(
      studio,
      vocabularies: [const WordSet.open('chat'), const WordSet.open('clip')],
    );
    final line = p.defineFact(
      FactDescriptor('chat.line', type: const TextType()),
    );
    final last = p.defineState(
      StateDescriptor('clip.last', type: const TextType()),
    );
    p.defineCommand(
      CommandDescriptor('chat.say', callers: Callers.only(['viewer'])),
      (c) => line.emit('!clip', cause: c.causeFor(studio)),
    );
    p.defineCommand(
      CommandDescriptor(
        'clip.save',
        params: const ObjectType({'len': Field(IntType())}),
        callers: Callers.only(['plugin']),
      ),
      (c) => last.set('clip-${c.params['len']}', cause: c.causeFor(studio)),
    );
    p.defineCommand(
      CommandDescriptor('clip.cover', callers: Callers.only(['user'])),
      (_) {},
    );
    final plugin = r.participant(basics);
    plugin.facts('chat.line').listen((f) async {
      await plugin.call('clip.save', {
        'len': 90,
      }, cause: Cause(basics, parent: f.id));
      await plugin.call('clip.cover', {}, cause: Cause(basics, parent: f.id));
    });
    last.set('none');
  }

  final Registry r;

  Future<void> chat(String id) async {
    await r.participant(viewer).call('chat.say', {}, id: id);
    await pumpEventQueue();
  }
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('journal'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('a conversation written as it happened is read back whole, in '
      'order', () async {
    final s = Studio();
    final w = JournalWriter(s.r.journal, dir: dir);
    await s.chat('irc:1');
    await s.chat('irc:2');
    await w.close();
    await s.r.dispose();

    final talk = JournalReader(dir).conversation('irc:1');
    String line(JournalEntry e) => switch (e) {
      JournalStart(:final call) => 'start ${call.command} ${call.cause.by}',
      JournalEnd(:final call) =>
        'end ${call.command} ${call.result.toJson().keys.first}',
      JournalFact(:final fact) => 'fact ${fact.fact}',
      JournalWrite(:final change) => 'write ${change.state}=${change.value}',
    };
    expect(talk.map(line), [
      'start chat.say viewer/twitch.7',
      'fact chat.line',
      'end chat.say done',
      'start clip.save plugin/basics',
      'write clip.last=clip-90',
      'end clip.save done',
      'end clip.cover refused',
    ]);
    expect(
      talk.map((e) => e.n),
      orderedEquals([...talk.map((e) => e.n)]..sort()),
    );
  });

  test('a cause made by hand whose parent the registry forgot still '
      'follows from it', () async {
    final r = Registry();
    final p = r.participant(studio, vocabularies: [const WordSet.open('x')]);
    final said = p.defineFact(FactDescriptor('x.said', type: const TextType()));
    p.defineCommand(
      CommandDescriptor('x.do', callers: Callers.only(['user'])),
      (_) {},
    );
    final w = JournalWriter(r.journal, dir: dir);
    said.emit('a', id: 'f1');
    await pumpEventQueue();
    // As if the registry had forgotten f1: a conversation of its own.
    await r
        .participant(user)
        .call(
          'x.do',
          {},
          cause: const Cause(user, parent: 'f1', conversation: 'other'),
        );
    await w.close();
    await r.dispose();
    expect(JournalReader(dir).conversation('f1').map((e) => e.kind), [
      'fact',
      'start',
      'end',
    ]);
  });

  test('without payloads it keeps who did what and how it ended, no '
      'values', () async {
    final s = Studio();
    final w = JournalWriter(s.r.journal, dir: dir, payloads: false);
    await s.chat('irc:1');
    await w.close();
    await s.r.dispose();
    final text = File(JournalReader(dir).files.single.path).readAsStringSync();
    expect(text, isNot(contains('clip-90')));
    expect(text, isNot(contains('!clip')));
    expect(text, isNot(contains('"len"')));
    final talk = JournalReader(dir).conversation('irc:1');
    expect(talk, hasLength(7));
    final save = talk.whereType<JournalStart>().last.call;
    expect(save.command, 'clip.save');
    expect(save.params, isEmpty);
  });

  test('the links there are: who calls what, following what, refusals '
      'apart', () async {
    final s = Studio();
    final w = JournalWriter(s.r.journal, dir: dir);
    await s.chat('irc:1');
    await s.chat('irc:2');
    await w.close();
    await s.r.dispose();
    expect(
      JournalReader(dir).links().map((l) => '$l'),
      unorderedEquals([
        '- -> viewer/twitch.7 -> chat.say x2',
        'chat.say -> studio -> chat.line x2',
        'chat.line -> plugin/basics -> clip.save x2',
        'chat.line -> plugin/basics -> clip.cover x0 (refused x2)',
      ]),
    );
  });

  test('a trace from telemetry leads back to what was done', () async {
    final logs = LogController();
    final spans = <LogSpan>[];
    logs.stream.listen((r) {
      if (r is LogSpan) spans.add(r);
    });
    final s = Studio(log: logs.scope('studio'));
    final w = JournalWriter(s.r.journal, dir: dir);
    await s.chat('irc:1');
    await w.close();
    await s.r.dispose();
    final save = spans.singleWhere((s) => s.name == 'clip.save');
    expect(save.data, containsPair('conversation', 'irc:1'));
    final traced = JournalReader(dir).trace(save.traceId!);
    expect(
      traced.map((e) => e.kind),
      containsAllInOrder(['start', 'write', 'end']),
    );
    expect({for (final e in traced) e.conversation}, {'irc:1'});
    logs.dispose();
  });

  test('a file a day; days older than kept go; a line cut short is '
      'skipped', () async {
    File('${dir.path}/journal-2026-01-01.jsonl').writeAsStringSync('{}\n');
    File('${dir.path}/journal-2026-10-27.jsonl').writeAsStringSync('{"epo');
    File('${dir.path}/notes.txt').writeAsStringSync('mine');
    final s = Studio();
    final w = JournalWriter(
      s.r.journal,
      dir: dir,
      keep: const Duration(days: 7),
      now: () => DateTime.utc(2026, 10, 28),
    );
    await s.chat('irc:1');
    await w.close();
    await s.r.dispose();
    final names = [for (final f in dir.listSync()) f.uri.pathSegments.last]
      ..sort();
    expect(names.first, 'journal-2026-10-27.jsonl');
    expect(names, contains('notes.txt'));
    expect(names, isNot(contains('journal-2026-01-01.jsonl')));
    expect(JournalReader(dir).conversation('irc:1'), hasLength(7));
  });
}
