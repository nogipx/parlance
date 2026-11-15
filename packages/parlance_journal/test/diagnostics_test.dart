import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:parlance/tools.dart';
import 'package:parlance/src/registry/messages.dart' show keptChange;
import 'package:parlance_journal/parlance_journal.dart';
import 'package:test/test.dart';

JournalStart start(String epoch, {int n = 1}) => JournalStart(
  CallStarted(
    id: 'same',
    command: 'house.run',
    params: {},
    cause: const Cause(Principal('user')),
    started: DateTime.utc(2026),
  ),
  epoch: epoch,
  n: n,
);

final class _Shape extends Shape<String> {
  var encoded = 0;
  @override
  ValueType<Object?> get type => const TextType();
  @override
  Object? toJson(String value) {
    encoded++;
    return value;
  }

  @override
  String fromJson(Object? value) => value! as String;
  @override
  String check(String value, {String? was}) => value;
  @override
  bool equals(String a, String b) => a == b;
  @override
  int weigh(String value) => value.length;
}

void main() {
  test(
    'historical lookups require an epoch when a message ID is ambiguous',
    () {
      final journal = Journal([start('one'), start('two')]);
      expect(() => journal.of('same'), throwsArgumentError);
      expect(() => journal.pathTo('same'), throwsArgumentError);
      expect(() => journal.tree('same'), throwsArgumentError);
      expect(journal.of('same', epoch: 'one').single.epoch, 'one');
      expect(journal.pathTo('same', epoch: 'two').single.epoch, 'two');
    },
  );

  test('ID ambiguity affects only paths which reference that ID', () {
    final other = JournalStart(
      CallStarted(
        id: 'other',
        command: 'house.run',
        params: {},
        cause: const Cause(Principal('user')),
        started: DateTime.utc(2026),
      ),
      epoch: 'one',
      n: 3,
    );
    final journal = Journal([start('one'), start('one', n: 2), other]);
    expect(() => journal.pathTo('same'), throwsArgumentError);
    expect(journal.pathTo('other').single.id, 'other');
    expect(
      treeOf(
        journal.entries,
      ).where((n) => n.id == 'same').every((n) => n.ambiguous),
      isTrue,
    );
  });

  test('sequence gaps across daily files are reported by the reader', () {
    final dir = Directory.systemTemp.createTempSync('parlance-boundary');
    addTearDown(() => dir.deleteSync(recursive: true));
    File(
      '${dir.path}/journal-2026-11-14.jsonl',
    ).writeAsStringSync(_json(start('one').toJson()));
    File(
      '${dir.path}/journal-2026-11-15.jsonl',
    ).writeAsStringSync(_json(start('one', n: 3).toJson()));
    final issues = <JournalIssue>[];
    expect(JournalReader(dir, onIssue: issues.add).entries(), hasLength(2));
    expect(issues.single.reason, contains('1 -> 3'));
  });

  test('admission events connect even when they precede handler start', () {
    final decision = JournalDiagnostic(
      id: 'decision',
      word: 'house.run',
      cause: const Cause(
        Principal('user'),
        parent: 'same',
        conversation: 'same',
      ),
      at: DateTime.utc(2026),
      event: 'attempt',
      data: {'operation': 'same'},
      epoch: 'one',
      n: 1,
    );
    final roots = treeOf([decision, start('one', n: 2)]);
    expect(roots, hasLength(1));
    expect(roots.single.decisions.single.id, 'decision');
    expect(roots.single.children, isEmpty);
  });

  test('late completion preserves what the caller received', () {
    final begun = start('one');
    final ended = JournalEnd(
      CallRecord(
        id: 'same',
        command: 'house.run',
        params: {},
        cause: begun.cause,
        result: const CallDone(null),
        started: begun.at,
        finished: begun.at.add(const Duration(seconds: 2)),
        late: true,
        replyResult: const CallTimedOut(),
        repliedAt: begun.at.add(const Duration(seconds: 1)),
      ),
      epoch: 'one',
      n: 3,
    );
    final node = treeOf([begun, ended]).single;
    expect(node.end!.call.replyResult, isA<CallTimedOut>());
    expect(node.toJson()['replyResult'], {'timedOut': true});
  });

  test(
    'metadata-only recording never serializes native state values',
    () async {
      final dir = Directory.systemTemp.createTempSync('parlance-metadata');
      addTearDown(() => dir.deleteSync(recursive: true));
      final shape = _Shape();
      final change = keptChange(
        seq: 1,
        id: 'write',
        state: 'house.state',
        key: null,
        value: 'private',
        previous: 'before',
        removed: false,
        cause: const Cause(Principal('house')),
        at: DateTime.now().toUtc(),
        shape: shape,
      );
      final writer = JournalWriter(
        Stream.value(JournalWrite(change, epoch: 'one', n: 1)),
        dir: dir,
        payloads: false,
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await writer.close();
      expect(shape.encoded, 0);
      final entries = JournalReader(dir).entries().toList();
      final written = entries.whereType<JournalWrite>().single;
      expect(written.payloads, isFalse);
      expect(written.toJson(), isNot(contains('value')));
      expect(
        entries.whereType<JournalDiagnostic>().map((e) => e.event),
        containsAll(['capture.started', 'capture.stopped']),
      );
    },
  );

  test(
    'parse reports malformed lines and sequence gaps without retaining source payloads',
    () {
      final issues = <JournalIssue>[];
      final json = start('one').toJson();
      final valid = JournalDiagnostic(
        id: 'd',
        word: 'house.run',
        cause: const Cause(Principal('house')),
        at: DateTime.utc(2026),
        event: 'attempt',
        epoch: 'one',
        n: 3,
      );
      // JSON text is produced by the same model as a recorder.
      final input =
          '${_json(json)}\nprivate-payload-not-JSON\n${_json(valid.toJson())}\n';
      final entries = parseJournal(input, onIssue: issues.add).toList();
      expect(entries, hasLength(2));
      expect(issues, hasLength(2));
      expect(issues.last.reason, contains('1 -> 3'));
      expect(issues.first.reason, isNot(contains('private-payload')));
      expect(issues.every((i) => i.reason.length <= 256), isTrue);
    },
  );
}

String _json(Object? value) => const JsonEncoder().convert(value);
