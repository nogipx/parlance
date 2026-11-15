import 'dart:io';

import 'package:clock/clock.dart';
import 'package:parlance/app.dart' show Host;
import 'package:parlance/tools.dart';
import 'package:parlance_journal/parlance_journal.dart';
import 'package:rpc_dart/logger.dart';
import 'package:test/test.dart';

const house = Principal('house');
const user = Principal('user', 'local');
const visitor = Principal('visitor', 'gate.7');
const basics = Principal('plugin', 'basics');

/// A house of a intercom line, a clip saved in answer and a cover only the
/// user may set: what a journal of it keeps.
final class House {
  House({LogScope? log}) : host = Host(log: log) {
    final p = host
        .participant(
          house,
          vocabularies: [
            const WordSet.open('intercom'),
            const WordSet.open('clip'),
          ],
        )
        .raw;
    final line = p.defineFact(
      FactDescriptor('house/intercom.line', type: const TextType()),
    );
    final last = p.defineState(
      StateDescriptor('house/clip.last', type: const TextType()),
    );
    p.defineCommand(
      CommandDescriptor(
        'house/intercom.say',
        callers: Callers.only(['visitor']),
      ),
      (c) => line.say('!clip', cause: c.causeFor(house)),
    );
    p.defineCommand(
      CommandDescriptor(
        'house/clip.save',
        params: const RecordType({'len': Field(IntType())}),
        callers: Callers.only(['plugin']),
      ),
      (c) => last.set('clip-${c.params['len']}', cause: c.causeFor(house)),
    );
    p.defineCommand(
      CommandDescriptor('house/clip.cover', callers: Callers.only(['user'])),
      (_) {},
    );
    final plugin = host.participant(basics).raw;
    plugin.facts('house/intercom.line').listen((f) async {
      await plugin.call('house/clip.save', {
        'len': 90,
      }, cause: Cause(basics, parent: f.id));
      await plugin.call(
        'house/clip.cover',
        {},
        cause: Cause(basics, parent: f.id),
      );
    });
    last.set('none');
  }

  final Host host;
  Registry get r => host.registry;

  Future<void> intercom(String id) async {
    await host.participant(visitor).raw.call('house/intercom.say', {}, id: id);
    await pumpEventQueue();
  }
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('journal'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('a conversation written as it happened is read back whole, in '
      'order', () async {
    final s = House();
    final w = JournalWriter(s.r.journal, dir: dir);
    await s.intercom('irc:1');
    await s.intercom('irc:2');
    await w.close();
    await s.r.dispose();

    final talk = JournalReader(dir).conversation('visitor/gate.7#irc:1');
    String line(JournalEntry e) => switch (e) {
      JournalDiagnostic(:final event) => 'diagnostic $event',
      JournalStart(:final call) => 'start ${call.command} ${call.cause.by}',
      JournalEnd(:final call) =>
        'end ${call.command} ${call.result.toJson().keys.first}',
      JournalFact(:final fact) => 'fact ${fact.fact}',
      JournalWrite(:final change) => 'write ${change.state}=${change.value}',
    };
    expect(talk.where((e) => e is! JournalDiagnostic).map(line), [
      'start house/intercom.say visitor/gate.7',
      'fact house/intercom.line',
      'end house/intercom.say done',
      'start house/clip.save plugin/basics',
      'write house/clip.last=clip-90',
      'end house/clip.save done',
      'end house/clip.cover refused',
    ]);
    expect(
      talk.map((e) => e.n),
      orderedEquals([...talk.map((e) => e.n)]..sort()),
    );
  });

  test('every word a conversation led to, found by the word it started '
      'with and by whom', () async {
    final s = House();
    final w = JournalWriter(s.r.journal, dir: dir);
    await s.intercom('irc:1');
    await s.intercom('irc:2');
    await w.close();
    await s.r.dispose();
    final led = JournalReader(
      dir,
    ).startedWith('house/intercom.say', by: visitor);
    expect(
      {for (final e in led) e.conversation},
      {'visitor/gate.7#irc:1', 'visitor/gate.7#irc:2'},
    );
    expect(
      {for (final e in led) e.word},
      {
        'house/intercom.say',
        'house/intercom.line',
        'house/clip.save',
        'house/clip.last',
        'house/clip.cover',
      },
    );
    expect(
      {for (final e in led) e.origin},
      {const Origin('house/intercom.say', visitor)},
    );
    expect(
      JournalReader(dir).startedWith('house/intercom.say', by: user),
      isEmpty,
    );
  });

  test('from any message: the conversation it was in, and how it came '
      'about', () async {
    final s = House();
    final w = JournalWriter(s.r.journal, dir: dir);
    await s.intercom('irc:1');
    await s.intercom('irc:2');
    await w.close();
    await s.r.dispose();
    final reader = JournalReader(dir);
    final write = reader
        .conversation('visitor/gate.7#irc:1')
        .whereType<JournalWrite>()
        .single;
    final talk = reader.of(write.id);
    expect({for (final e in talk) e.conversation}, {'visitor/gate.7#irc:1'});
    expect(talk, hasLength(13));
    expect(reader.pathTo(write.id).map((e) => '${e.kind} ${e.word}'), [
      'start house/intercom.say',
      'fact house/intercom.line',
      'start house/clip.save',
      'write house/clip.last',
    ]);
    final refused = reader
        .conversation('visitor/gate.7#irc:2')
        .whereType<JournalEnd>()
        .singleWhere((e) => e.call.result is CallRefused);
    expect(reader.pathTo(refused.id).map((e) => '${e.kind} ${e.word}'), [
      'start house/intercom.say',
      'fact house/intercom.line',
      'end house/clip.cover',
    ]);
    expect(reader.of('nothing'), isEmpty);
    expect(reader.pathTo('nothing'), isEmpty);
  });

  test('a conversation as a tree: what each message led to under it, a '
      'call with how it ended', () async {
    final s = House();
    final w = JournalWriter(s.r.journal, dir: dir);
    await s.intercom('irc:1');
    await w.close();
    await s.r.dispose();
    String draw(JournalNode n, [String indent = '']) => [
      '$indent${n.kind} ${n.word} by ${n.by}'
          '${n.end == null ? '' : ' -> ${n.end!.call.result.toJson().keys.first}'}',
      for (final c in n.children) draw(c, '$indent  '),
    ].join('\n');
    final roots = JournalReader(dir).tree('visitor/gate.7#irc:1');
    expect(roots.map(draw).join('\n'), '''
call house/intercom.say by visitor/gate.7 -> done
  fact house/intercom.line by house
    call house/clip.save by plugin/basics -> done
      write house/clip.last by house
    call house/clip.cover by plugin/basics -> refused''');
    final json = roots.single.toJson();
    expect(json, containsPair('word', 'house/intercom.say'));
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
    final host = Host();
    final r = host.registry;
    final p = host
        .participant(house, vocabularies: [const WordSet.open('x')])
        .raw;
    final said = p.defineFact(
      FactDescriptor('house/x.said', type: const TextType()),
    );
    p.defineCommand(
      CommandDescriptor('house/x.do', callers: Callers.only(['user'])),
      (_) {},
    );
    final w = JournalWriter(r.journal, dir: dir);
    said.say('a', id: 'f1');
    await pumpEventQueue();
    // As if the registry had forgotten f1: a conversation of its own.
    await host
        .participant(user)
        .raw
        .call(
          'house/x.do',
          {},
          cause: const Cause(
            user,
            parent: 'house/x.said#f1',
            conversation: 'other',
          ),
        );
    await w.close();
    await host.dispose();
    expect(
      JournalReader(dir).conversation('house/x.said#f1').map((e) => e.kind),
      ['fact', 'start', 'end'],
    );
  });

  test('without payloads it keeps who did what and how it ended, no '
      'values', () async {
    final s = House();
    final w = JournalWriter(s.r.journal, dir: dir, payloads: false);
    await s.intercom('irc:1');
    await w.close();
    await s.r.dispose();
    final text = File(JournalReader(dir).files.single.path).readAsStringSync();
    expect(text, isNot(contains('clip-90')));
    expect(text, isNot(contains('!clip')));
    expect(text, isNot(contains('"len"')));
    final talk = JournalReader(dir).conversation('visitor/gate.7#irc:1');
    expect(talk, hasLength(13));
    final save = talk.whereType<JournalStart>().last.call;
    expect(save.command, 'house/clip.save');
    expect(save.params, isEmpty);
  });

  test('the links there are: who calls what, following what, refusals '
      'apart', () async {
    final s = House();
    final w = JournalWriter(s.r.journal, dir: dir);
    await s.intercom('irc:1');
    await s.intercom('irc:2');
    await w.close();
    await s.r.dispose();
    expect(
      JournalReader(dir).links().map((l) => '$l'),
      unorderedEquals([
        '- -> visitor/gate.7 -> house/intercom.say x2',
        'house/intercom.say -> house -> house/intercom.line x2',
        'house/intercom.line -> plugin/basics -> house/clip.save x2',
        'house/intercom.line -> plugin/basics -> house/clip.cover x0 (refused x2)',
      ]),
    );
  });

  test('a trace from telemetry leads back to what was done', () async {
    final logs = LogController();
    final spans = <LogSpan>[];
    logs.stream.listen((r) {
      if (r is LogSpan) spans.add(r);
    });
    final s = House(log: logs.scope('house'));
    final w = JournalWriter(s.r.journal, dir: dir);
    await s.intercom('irc:1');
    await w.close();
    await s.r.dispose();
    final save = spans.singleWhere((s) => s.name == 'house/clip.save');
    expect(save.data, containsPair('conversation', 'visitor/gate.7#irc:1'));
    final traced = JournalReader(dir).trace(save.traceId!);
    expect(
      traced.map((e) => e.kind),
      containsAllInOrder(['start', 'write', 'end']),
    );
    expect({for (final e in traced) e.conversation}, {'visitor/gate.7#irc:1'});
    logs.dispose();
  });

  test('off, nothing is written, and the registry makes no entry; on '
      'again, it goes on from then', () async {
    final s = House();
    final w = JournalWriter(s.r.journal, dir: dir, on: false);
    await s.intercom('irc:1');
    expect(dir.listSync(), isEmpty);
    w.on = true;
    await s.intercom('irc:2');
    w.on = false;
    await s.intercom('irc:3');
    await w.close();
    w.on = true;
    await s.intercom('irc:4');
    await s.r.dispose();
    final talks = {
      for (final e in JournalReader(dir).entries())
        if (e is! JournalDiagnostic || !e.event.startsWith('capture.'))
          e.conversation,
    };
    expect(talks, {'visitor/gate.7#irc:2'});
  });

  test('the same questions of lines read anywhere, in a browser too; each '
      'conversation in brief', () async {
    final s = House();
    final w = JournalWriter(s.r.journal, dir: dir);
    await s.intercom('irc:1');
    await s.intercom('irc:2');
    await w.close();
    await s.r.dispose();
    final text = JournalReader(dir).files.single.readAsStringSync();
    final j = Journal.parse('$text{"cut sh');
    expect(j.entries, hasLength(JournalReader(dir).entries().length));
    expect(j.conversation('visitor/gate.7#irc:1'), hasLength(13));
    expect(j.tree('visitor/gate.7#irc:1').single.word, 'house/intercom.say');
    final talks = j.conversations();
    expect(talks.map((c) => c.id), [
      'visitor/gate.7#irc:1',
      'visitor/gate.7#irc:2',
    ]);
    final first = talks.first;
    expect(first.origin, const Origin('house/intercom.say', visitor));
    expect(
      (first.entries, first.calls, first.refused, first.failed),
      (13, 3, 1, 0),
    );
    expect(first.duration, first.last.difference(first.started));
    expect(first.epoch, isNotEmpty);
  });

  test('the days asked for, exported as one file a visitor reads as it '
      'reads the days', () async {
    File('${dir.path}/journal-2026-10-26.jsonl').writeAsStringSync('old\n');
    final s = House();
    final w = JournalWriter(s.r.journal, dir: dir);
    await s.intercom('irc:1');
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
    expect(n, 15);
    expect(
      Journal.parse(
        out.readAsStringSync(),
      ).conversation('visitor/gate.7#irc:1'),
      hasLength(13),
    );
    expect(await JournalReader(dir).export(out), 16, reason: 'all days');
    final none = File('${out.path}.none');
    expect(await JournalReader(dir).export(none, until: DateTime.utc(2000)), 0);
    expect(none.existsSync(), isFalse);
  });

  test('a file a day; days older than kept go; a line cut short is '
      'skipped', () async {
    File('${dir.path}/journal-2026-01-01.jsonl').writeAsStringSync('{}\n');
    File('${dir.path}/journal-2026-10-27.jsonl').writeAsStringSync('{"epo');
    File('${dir.path}/notes.txt').writeAsStringSync('mine');
    final s = House();
    final w = JournalWriter(
      s.r.journal,
      dir: dir,
      keep: const Duration(days: 7),
      now: () => DateTime.utc(2026, 10, 28),
    );
    await s.intercom('irc:1');
    await w.close();
    await s.r.dispose();
    final names = [for (final f in dir.listSync()) f.uri.pathSegments.last]
      ..sort();
    expect(names.first, 'journal-2026-10-27.jsonl');
    expect(names, contains('notes.txt'));
    expect(names, isNot(contains('journal-2026-01-01.jsonl')));
    expect(
      JournalReader(dir).conversation('visitor/gate.7#irc:1'),
      hasLength(13),
    );
  });
  test('an entry after a line cut short is a line of its own', () async {
    final today = File(
      '${dir.path}/journal-${DateTime.now().toUtc().toIso8601String().substring(0, 10)}.jsonl',
    )..writeAsStringSync('{"epo');
    final s = House();
    final w = JournalWriter(s.r.journal, dir: dir);
    await s.intercom('irc:1');
    await w.close();
    await s.r.dispose();
    expect(
      JournalReader(dir).conversation('visitor/gate.7#irc:1'),
      hasLength(13),
    );
    expect(today.readAsLinesSync().first, '{"epo');
  });

  test('a character cut short loses its line, not its day', () async {
    final s = House();
    final w = JournalWriter(s.r.journal, dir: dir);
    await s.intercom('irc:1');
    await w.close();
    await s.r.dispose();
    final day = JournalReader(dir).files.single;
    day.writeAsBytesSync([...'{"x":"'.codeUnits, 0xD0], mode: FileMode.append);
    expect(
      JournalReader(dir).conversation('visitor/gate.7#irc:1'),
      hasLength(13),
    );
    final out = File('${dir.path}/out.jsonl');
    expect(await JournalReader(dir).export(out), 16);
  });

  test('a day whose file would not open is written once it opens', () async {
    var now = DateTime.utc(2026, 10, 27, 23);
    final host = Host(clock: Clock(() => now));
    final r = host.registry;
    host
        .participant(house, vocabularies: [const WordSet.open('clip')])
        .raw
        .defineCommand(
          CommandDescriptor(
            'house/clip.cover',
            callers: Callers.only(['user']),
          ),
          (_) {},
        );
    final errors = <Object>[];
    final w = JournalWriter(
      r.journal,
      dir: dir,
      onError: (e, _) => errors.add(e),
    );
    Future<void> cover(String id) async {
      await host.participant(user).raw.call('house/clip.cover', {}, id: id);
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
    await host.dispose();
    expect(errors, hasLength(failed), reason: 'it came back');
    expect(
      {
        for (final e in JournalReader(
          dir,
        ).days().entries.whereType<JournalEnd>())
          e.id,
      },
      {'user/local#a', 'user/local#c'},
    );
  });
  group('when the disk fails', () {
    test(
      'a folder it may not write in at first is written once it may',
      () async {
        final errors = <Object>[];
        final s = House();
        final w = JournalWriter(
          s.r.journal,
          dir: dir,
          onError: (e, _) => errors.add(e),
        );
        Process.runSync('chmod', ['500', dir.path]);
        await s.intercom('irc:1');
        expect(errors, isNotEmpty);
        Process.runSync('chmod', ['700', dir.path]);
        await s.intercom('irc:2');
        await w.close();
        await s.r.dispose();
        final read = JournalReader(dir);
        expect(read.conversation('visitor/gate.7#irc:1'), isEmpty);
        expect(
          read.conversation('visitor/gate.7#irc:2'),
          hasLength(12),
          reason: 'no write: the clip is as it was',
        );
      },
    );

    test('a folder removed while it writes is made again', () async {
      final s = House();
      final w = JournalWriter(s.r.journal, dir: dir);
      await s.intercom('irc:1');
      dir.deleteSync(recursive: true);
      await s.intercom('irc:2');
      await w.close();
      await s.r.dispose();
      expect(
        JournalReader(dir).conversation('visitor/gate.7#irc:2'),
        hasLength(12),
      );
    });

    test(
      'bytes that are no lines of it lose those lines, not the rest',
      () async {
        final s = House();
        final w = JournalWriter(s.r.journal, dir: dir);
        await s.intercom('irc:1');
        await w.close();
        await s.r.dispose();
        File(
          '${dir.path}/journal-2000-01-01.jsonl',
        ).writeAsBytesSync([0, 1, 2, 0xff, 10, ...'{"a":1}\n'.codeUnits, 0xc3]);
        expect(
          JournalReader(dir).conversation('visitor/gate.7#irc:1'),
          hasLength(13),
        );
        expect(JournalReader(dir).entries(), hasLength(15));
      },
    );

    test('a day it may not read is passed over, the others read', () async {
      final s = House();
      final w = JournalWriter(s.r.journal, dir: dir);
      await s.intercom('irc:1');
      await w.close();
      await s.r.dispose();
      final locked = File('${dir.path}/journal-2000-01-01.jsonl')
        ..writeAsStringSync('{}\n');
      Process.runSync('chmod', ['000', locked.path]);
      addTearDown(() => Process.runSync('chmod', ['600', locked.path]));
      expect(
        JournalReader(dir).conversation('visitor/gate.7#irc:1'),
        hasLength(13),
      );
      final out = File('${dir.path}/out.jsonl');
      expect(await JournalReader(dir).export(out), 15);
    });
  });

  test('a conversation in brief counts cancelled and lost among how its '
      'calls ended', () async {
    final host = Host();
    final r = host.registry;
    host
        .participant(house, vocabularies: [const WordSet.open('x')])
        .raw
        .defineCommand(
          CommandDescriptor('house/x.slow', callers: Callers.only(['user'])),
          (_) {},
        );
    final w = JournalWriter(r.journal, dir: dir);
    final token = CancellationToken();
    final call = host
        .participant(user)
        .raw
        .call('house/x.slow', const {}, cancel: token);
    token.cancel();
    await call;
    await pumpEventQueue();
    await w.close();
    await host.dispose();
    // One whose answer was lost on the way, as a newer build writes it: a
    // start and an end it did not get an answer to.
    JournalReader(dir).files.last.writeAsStringSync(
      '{"epoch":"e1","n":1,"kind":"start","id":"w1","command":"x.slow",'
      '"params":{},"cause":{"by":{"kind":"user","id":"local"}},'
      '"started":"2026-10-31T00:00:00.000Z"}\n'
      '{"epoch":"e1","n":2,"kind":"end","id":"w1","command":"x.slow",'
      '"params":{},"cause":{"by":{"kind":"user","id":"local"}},'
      '"result":{"lost":"w1","reason":"the way broke"},'
      '"started":"2026-10-31T00:00:00.000Z",'
      '"finished":"2026-10-31T00:00:01.000Z"}\n',
      mode: FileMode.append,
    );
    final talks = JournalReader(dir).days().conversations();
    final cancelled = talks.singleWhere(
      (JournalConversation c) => c.cancelled == 1,
    );
    expect(cancelled.failed, 0, reason: 'not a failure');
    final lost = talks.singleWhere((JournalConversation c) => c.lost == 1);
    expect((lost.calls, lost.failed), (1, 0));
  });

  test(
    'a line of a kind this build does not know is skipped, and told',
    () async {
      final s = House();
      final w = JournalWriter(s.r.journal, dir: dir);
      await s.intercom('irc:1');
      await w.close();
      await s.r.dispose();
      final today = JournalReader(dir).files.last;
      today.writeAsStringSync(
        '{"epoch":"e","n":99,"kind":"wave","what":1}\n',
        mode: FileMode.append,
      );
      final told = <String>[];
      final read = JournalReader(dir, onUnknown: (kind, _) => told.add(kind));
      expect(read.conversation('visitor/gate.7#irc:1'), hasLength(13));
      expect(told, ['wave']);
      final j = Journal.parse(
        today.readAsStringSync(),
        onUnknown: (kind, _) => told.add(kind),
      );
      expect(j.entries, hasLength(15));
      expect(told, ['wave', 'wave'], reason: 'every one, to the callback');
    },
  );
}
