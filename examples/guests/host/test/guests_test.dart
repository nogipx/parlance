import 'dart:io';

import 'package:board_guest/board_guest.dart';
import 'package:guests_host/host.dart';
import 'package:guests_host/in_memory.dart';
import 'package:notes_guest/notes_guest.dart';
import 'package:notes_words/notes_words.dart';
import 'package:parlance/app.dart';
import 'package:parlance/tools.dart'
    show
        HostRegistry,
        RawAccess,
        CommandDescriptor,
        StateDescriptor,
        WordAddress;
import 'package:test/test.dart';

/// Two guests of one host: the notes guest gives its words, the board
/// guest uses the app's and the notes', typed, knowing neither but by their
/// words packages; what goes between them is the host's to see.

void main() {
  late Shell host;
  final mismatches = <String, String>{};

  setUp(() {
    host = Shell();
    mismatches.clear();
  });
  tearDown(() async {
    await host.dispose();
    await closeInMemory();
  });

  Future<(IRemoteParticipant, Board)> board() => loadInMemory(
    host: host,
    id: 'board',
    start: (e) => startBoard(
      e,
      appProvider: Who.app,
      notesProvider: Who.widlet('notes'),
      onError: (x) {
        if (x.code == ParticipantErrorCode.mismatch) {
          mismatches['${x.op['word']}'] = x.why;
        }
      },
    ),
  );

  test('a guest uses another guest\'s words and the host\'s, typed', () async {
    await loadInMemory(
      host: host,
      id: 'notes',
      vocabularies: [notesWords],
      start: startNotes,
    );
    final (p, b) = await board();
    final heard = b.notes.added.payloads.first;
    await b.pin('buy milk');
    await p.settle();
    expect(b.shown.single.text, 'buy milk');
    expect((await heard).text, 'buy milk');
    expect(host.app.toasts, ['pinned: buy milk']);
    expect(mismatches, isEmpty);
    expect(host.host.registry.mismatches, isEmpty);
    await b.close();
  });

  test(
    'two instances of the same notes guest have independent words and data',
    () async {
      final work = await loadInMemory(
        host: host,
        id: 'work',
        vocabularies: [notesWords],
        start: startNotes,
      );
      final personal = await loadInMemory(
        host: host,
        id: 'personal',
        vocabularies: [notesWords],
        start: startNotes,
      );
      final user = host.host.participant(Who.user);
      final a = INotesClient(participant: user, provider: Who.widlet('work'));
      final b = INotesClient(
        participant: user,
        provider: Who.widlet('personal'),
      );
      await a.add(text: 'work item');
      await b.add(text: 'personal item');
      await user.settle();
      expect(a.all.value!.single.text, 'work item');
      expect(b.all.value!.single.text, 'personal item');
      host.unload('work');
      await personal.settle();
      expect(a.status(NotesCommand.add), const WordMissing());
      expect(b.status(NotesCommand.add), const WordReady());
      await b.add(text: 'still here');
      expect(b.all.value, hasLength(2));
      await work.dispose();
    },
  );

  test('the host sees what one guest led the other to do', () async {
    await loadInMemory(
      host: host,
      id: 'notes',
      vocabularies: [notesWords],
      start: startNotes,
    );
    final (p, b) = await board();
    await b.pin('call ann');
    await p.settle();
    final why = host.host.registry.explain(
      WordAddress(Who.widlet('notes'), 'notes.all').toString(),
    );
    expect(why.change!.cause.by, Who.widlet('notes').ofOwner('notes'));
    expect(
      why.trail.first.command,
      WordAddress(Who.widlet('notes'), 'notes.add').toString(),
    );
    expect(why.trail.first.cause.by, Who.widlet('board'));
    await b.close();
  });

  test('a guest consumes another guest\'s finite typed stream', () async {
    await loadInMemory(
      host: host,
      id: 'notes',
      vocabularies: [notesWords],
      start: startNotes,
    );
    final (p, b) = await board();
    await b.pin('buy milk');
    await b.pin('call ann');
    await b.pin('milk for tomorrow');
    expect(await b.notes.search(text: 'milk').toList(), [
      (id: 'n1', text: 'buy milk'),
      (id: 'n3', text: 'milk for tomorrow'),
    ]);
    expect(await b.notes.search().length, 3);
    expect(await b.notes.search(text: 'absent').toList(), isEmpty);
    await p.settle();
    expect(mismatches, isEmpty);
    await b.close();
  });

  test(
    'a guest of another version is told, every difference at once',
    () async {
      // The notes guest as it was before: `notes.add` took a shorter text,
      // and its notes were texts alone.
      await loadInMemory(
        host: host,
        id: 'notes',
        vocabularies: [notesWords],
        start: (e) async {
          final p = await Host.joinEndpoint(e);
          p.raw.defineCommand(
            CommandDescriptor(
              WordAddress(Who.widlet('notes'), 'notes.add').toString(),
              params: const RecordType({
                'text': Field(TextType(maxLength: 100)),
              }),
              callers: Who.callers,
            ),
            (_) => null,
          );
          p.raw.defineState(
            StateDescriptor(
              WordAddress(Who.widlet('notes'), 'notes.all').toString(),
              type: const ListType(TextType()),
            ),
          );
          await p.settle();
          return p;
        },
      );
      final (p, b) = await board();
      await p.settle();
      expect(
        mismatches[WordAddress(Who.widlet('notes'), 'notes.add').toString()],
        contains('params.fields.text.type.maxLength: was 200, is 100'),
      );
      expect(
        mismatches[WordAddress(Who.widlet('notes'), 'notes.all').toString()],
        contains('type.item.type: was object, is text'),
      );
      expect(
        INotesClient(
          participant: p,
          provider: Who.widlet('notes'),
        ).mismatches.keys,
        {
          WordAddress(Who.widlet('notes'), 'notes.add').toString(),
          WordAddress(Who.widlet('notes'), 'notes.all').toString(),
        },
      );
      // The host is told it too, as the board is.
      for (final m in host.host.registry.mismatches) {
        if (m.by != Who.widlet('board')) continue;
        for (final b in m.breaks) {
          expect(mismatches[m.word], contains('$b'));
        }
      }
      await b.close();
    },
  );

  test('a guest that goes takes its words; one that comes again brings '
      'them, in any order', () async {
    final (p, b) = await board();
    expect(
      INotesClient(
        participant: p,
        provider: Who.widlet('notes'),
      ).status(NotesCommand.add),
      const WordMissing(),
    );
    final notes = await loadInMemory(
      host: host,
      id: 'notes',
      vocabularies: [notesWords],
      start: startNotes,
    );
    await p.settle();
    expect(
      INotesClient(
        participant: p,
        provider: Who.widlet('notes'),
      ).status(NotesCommand.add),
      const WordReady(),
    );
    host.unload('notes');
    await p.settle();
    expect(
      INotesClient(
        participant: p,
        provider: Who.widlet('notes'),
      ).status(NotesCommand.add),
      const WordMissing(),
    );
    await notes.dispose();
    await b.close();
  });

  test('a guest knows others by their words packages alone', () {
    final board = File('../board_guest/pubspec.yaml').readAsStringSync();
    final notes = File('../notes_guest/pubspec.yaml').readAsStringSync();
    expect(board, isNot(contains('notes_guest')));
    expect(board, isNot(contains('guests_host')));
    expect(notes, isNot(contains('board_guest')));
    expect(notes, isNot(contains('host_words')));
  });

  test('a guest defines in its own vocabulary only', () async {
    final (p, b) = await board();
    expect(
      () => GeneratedWords.own(p.raw).state(NotesState.all).define(),
      throwsA(isA<NotPermitted>()),
    );
    await b.close();
  });
}
