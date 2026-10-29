import 'dart:io';

import 'package:clock/clock.dart';
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

  test('every word a conversation led to, found by the word it started '
      'with and by whom', () async {
    final s = Studio();
    final w = JournalWriter(s.r.journal, dir: dir);
    await s.chat('irc:1');
    await s.chat('irc:2');
    await w.close();
    await s.r.dispose();
    final led = JournalReader(dir).startedWith('chat.say', by: viewer);
    expect({for (final e in led) e.conversation}, {'irc:1', 'irc:2'});
    expect(
      {for (final e in led) e.word},
      {'chat.say', 'chat.line', 'clip.save', 'clip.last', 'clip.cover'},
    );
    expect({for (final e in led) e.origin}, {const Origin('chat.say', viewer)});
    expect(JournalReader(dir).startedWith('chat.say', by: user), isEmpty);
  });

  test('from any message: the conversation it was in, and how it came '
      'about', () async {
    final s = Studio();
    final w = JournalWriter(s.r.journal, dir: dir);
    await s.chat('irc:1');
    await s.chat('irc:2');
    await w.close();
    await s.r.dispose();
    final reader = JournalReader(dir);
    final write = reader.conversation('irc:1').whereType<JournalWrite>().single;
    final talk = reader.of(write.id);
    expect({for (final e in talk) e.conversation}, {'irc:1'});
    expect(talk, hasLength(7));
    expect(reader.pathTo(write.id).map((e) => '${e.kind} ${e.word}'), [
      'start chat.say',
      'fact chat.line',
      'start clip.save',
      'write clip.last',
    ]);
    final refused = reader
        .conversation('irc:2')
        .whereType<JournalEnd>()
        .singleWhere((e) => e.call.result is CallRefused);
    expect(reader.pathTo(refused.id).map((e) => '${e.kind} ${e.word}'), [
      'start chat.say',
      'fact chat.line',
      'end clip.cover',
    ]);
    expect(reader.of('nothing'), isEmpty);
    expect(reader.pathTo('nothing'), isEmpty);
  });

  test('a conversation as a tree: what each message led to under it, a '
      'call with how it ended', () async {
    final s = Studio();
    final w = JournalWriter(s.r.journal, dir: dir);
    await s.chat('irc:1');
    await w.close();
    await s.r.dispose();
    String draw(JournalNode n, [String indent = '']) => [
      '$indent${n.kind} ${n.word} by ${n.by}'
          '${n.end == null ? '' : ' -> ${n.end!.call.result.toJson().keys.first}'}',
      for (final c in n.children) draw(c, '$indent  '),
    ].join('\n');
    final roots = JournalReader(dir).tree('irc:1');
    expect(roots.map(draw).join('\n'), '''
call chat.say by viewer/twitch.7 -> done
  fact chat.line by studio
    call clip.save by plugin/basics -> done
      write clip.last by studio
    call clip.cover by plugin/basics -> refused''');
    final json = roots.single.toJson();
    expect(json, containsPair('word', 'chat.say'));
    expect(json, containsPair('result', {'done': true}));
    expect(json['ms'], isA<int>());
    final saved =
        (((json['children'] as List).single as Map)['children'] as List).first
            as Map;
    expect(saved, isNot(contains('params')));
    final withValues = roots.single.toJson(payloads: true);
    final save =
        (((withValues['children'] as List).single as Map)['children'] as List)
                .first
            as Map;
    expect(save['params'], {'len': 90});
    expect(JournalReader(dir).tree('nothing'), isEmpty);
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

  test('off, nothing is written, and the registry makes no entry; on '
      'again, it goes on from then', () async {
    final s = Studio();
    final w = JournalWriter(s.r.journal, dir: dir, on: false);
    await s.chat('irc:1');
    expect(dir.listSync(), isEmpty);
    w.on = true;
    await s.chat('irc:2');
    w.on = false;
    await s.chat('irc:3');
    await w.close();
    w.on = true;
    await s.chat('irc:4');
    await s.r.dispose();
    final talks = {
      for (final e in JournalReader(dir).entries()) e.conversation,
    };
    expect(talks, {'irc:2'});
  });

  test('the same questions of lines read anywhere, in a browser too; each '
      'conversation in brief', () async {
    final s = Studio();
    final w = JournalWriter(s.r.journal, dir: dir);
    await s.chat('irc:1');
    await s.chat('irc:2');
    await w.close();
    await s.r.dispose();
    final text = JournalReader(dir).files.single.readAsStringSync();
    final j = Journal.parse('$text{"cut sh');
    expect(j.entries, hasLength(JournalReader(dir).entries().length));
    expect(j.conversation('irc:1'), hasLength(7));
    expect(j.tree('irc:1').single.word, 'chat.say');
    final talks = j.conversations();
    expect(talks.map((c) => c.id), ['irc:1', 'irc:2']);
    final first = talks.first;
    expect(first.origin, const Origin('chat.say', viewer));
    expect(
      (first.entries, first.calls, first.refused, first.failed),
      (7, 3, 1, 0),
    );
    expect(first.duration, first.last.difference(first.started));
    expect(first.epoch, isNotEmpty);
  });

  test('the days asked for, exported as one file a viewer reads as it '
      'reads the days', () async {
    File('${dir.path}/journal-2026-10-26.jsonl').writeAsStringSync('old\n');
    final s = Studio();
    final w = JournalWriter(s.r.journal, dir: dir);
    await s.chat('irc:1');
    await w.close();
    await s.r.dispose();
    final today = JournalReader(dir).files.last;
    final out = File(
      '${dir.path}/../export-${dir.uri.pathSegments[dir.uri.pathSegments.length - 2]}.jsonl',
    );
    addTearDown(() => out.existsSync() ? out.deleteSync() : null);
    final day = DateTime.parse(
      '${today.uri.pathSegments.last.substring(8, 18)}T12:00:00Z',
    );
    final n = await JournalReader(dir).export(out, since: day);
    expect(n, 7);
    expect(
      Journal.parse(out.readAsStringSync()).conversation('irc:1'),
      hasLength(7),
    );
    expect(await JournalReader(dir).export(out), 8, reason: 'all days');
    final none = File('${out.path}.none');
    expect(await JournalReader(dir).export(none, until: DateTime.utc(2000)), 0);
    expect(none.existsSync(), isFalse);
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
  test('an entry after a line cut short is a line of its own', () async {
    final today = File(
      '${dir.path}/journal-${DateTime.now().toUtc().toIso8601String().substring(0, 10)}.jsonl',
    )..writeAsStringSync('{"epo');
    final s = Studio();
    final w = JournalWriter(s.r.journal, dir: dir);
    await s.chat('irc:1');
    await w.close();
    await s.r.dispose();
    expect(JournalReader(dir).conversation('irc:1'), hasLength(7));
    expect(today.readAsLinesSync().first, '{"epo');
  });

  test('a character cut short loses its line, not its day', () async {
    final s = Studio();
    final w = JournalWriter(s.r.journal, dir: dir);
    await s.chat('irc:1');
    await w.close();
    await s.r.dispose();
    final day = JournalReader(dir).files.single;
    day.writeAsBytesSync([...'{"x":"'.codeUnits, 0xD0], mode: FileMode.append);
    expect(JournalReader(dir).conversation('irc:1'), hasLength(7));
    final out = File('${dir.path}/out.jsonl');
    expect(await JournalReader(dir).export(out), 8);
  });

  test('a day whose file would not open is written once it opens', () async {
    var now = DateTime.utc(2026, 10, 27, 23);
    final r = Registry(clock: Clock(() => now));
    r
        .participant(studio, vocabularies: [const WordSet.open('clip')])
        .defineCommand(
          CommandDescriptor('clip.cover', callers: Callers.only(['user'])),
          (_) {},
        );
    final errors = <Object>[];
    final w = JournalWriter(
      r.journal,
      dir: dir,
      onError: (e, _) => errors.add(e),
    );
    Future<void> cover(String id) async {
      await r.participant(user).call('clip.cover', {}, id: id);
      await pumpEventQueue();
    }

    await cover('a');
    final blocked = Directory('${dir.path}/journal-2026-10-28.jsonl')
      ..createSync();
    now = DateTime.utc(2026, 10, 28, 1);
    await cover('b');
    expect(errors, isNotEmpty);
    final failed = errors.length;
    blocked.deleteSync();
    await cover('c');
    await w.close();
    await r.dispose();
    expect(errors, hasLength(failed), reason: 'it came back');
    expect(
      {for (final e in JournalReader(dir).days().entries) e.id},
      {'a', 'c'},
    );
  });
  group('when the disk fails', () {
    test(
      'a folder it may not write in at first is written once it may',
      () async {
        final errors = <Object>[];
        final s = Studio();
        final w = JournalWriter(
          s.r.journal,
          dir: dir,
          onError: (e, _) => errors.add(e),
        );
        Process.runSync('chmod', ['500', dir.path]);
        await s.chat('irc:1');
        expect(errors, isNotEmpty);
        Process.runSync('chmod', ['700', dir.path]);
        await s.chat('irc:2');
        await w.close();
        await s.r.dispose();
        final read = JournalReader(dir);
        expect(read.conversation('irc:1'), isEmpty);
        expect(
          read.conversation('irc:2'),
          hasLength(6),
          reason: 'no write: the clip is as it was',
        );
      },
    );

    test('a folder removed while it writes is made again', () async {
      final s = Studio();
      final w = JournalWriter(s.r.journal, dir: dir);
      await s.chat('irc:1');
      dir.deleteSync(recursive: true);
      await s.chat('irc:2');
      await w.close();
      await s.r.dispose();
      expect(JournalReader(dir).conversation('irc:2'), hasLength(6));
    });

    test(
      'bytes that are no lines of it lose those lines, not the rest',
      () async {
        final s = Studio();
        final w = JournalWriter(s.r.journal, dir: dir);
        await s.chat('irc:1');
        await w.close();
        await s.r.dispose();
        File(
          '${dir.path}/journal-2000-01-01.jsonl',
        ).writeAsBytesSync([0, 1, 2, 0xff, 10, ...'{"a":1}\n'.codeUnits, 0xc3]);
        expect(JournalReader(dir).conversation('irc:1'), hasLength(7));
        expect(JournalReader(dir).entries(), hasLength(7));
      },
    );

    test('a day it may not read is passed over, the others read', () async {
      final s = Studio();
      final w = JournalWriter(s.r.journal, dir: dir);
      await s.chat('irc:1');
      await w.close();
      await s.r.dispose();
      final locked = File('${dir.path}/journal-2000-01-01.jsonl')
        ..writeAsStringSync('{}\n');
      Process.runSync('chmod', ['000', locked.path]);
      addTearDown(() => Process.runSync('chmod', ['600', locked.path]));
      expect(JournalReader(dir).conversation('irc:1'), hasLength(7));
      final out = File('${dir.path}/out.jsonl');
      expect(await JournalReader(dir).export(out), 7);
    });
  });
}
