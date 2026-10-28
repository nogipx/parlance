import 'dart:io';

import 'package:board_guest/board_guest.dart';
import 'package:guests_host/host.dart';
import 'package:guests_host/in_memory.dart';
import 'package:notes_guest/notes_guest.dart';
import 'package:notes_words/notes_words.dart';
import 'package:parlance/participant.dart';
import 'package:parlance/registry.dart';
import 'package:parlance/remote.dart';
import 'package:test/test.dart';

/// Two guests of one host: the notes guest gives its words, the board
/// guest uses the app's and the notes', typed, knowing neither but by their
/// words packages; what goes between them is the host's to see.
Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  late Host host;
  final mismatches = <String, List<String>>{};

  setUp(() {
    host = Host();
    mismatches.clear();
  });
  tearDown(() async {
    await host.dispose();
    await closeInMemory();
  });

  Future<(RemoteParticipant, Board)> board() => loadInMemory(
    host,
    'board',
    (e) => startBoard(
      e,
      onMismatch: (w, b) => mismatches[w] = [for (final x in b) '$x'],
    ),
  );

  test('a guest uses another guest\'s words and the host\'s, typed', () async {
    await loadInMemory(host, 'notes', startNotes);
    final (p, b) = await board();
    final heard = b.notes.added.first;
    await b.pin('buy milk');
    await p.flush();
    await settle();
    expect(b.shown.single.text, 'buy milk');
    expect((await heard).text, 'buy milk');
    expect(host.app.toasts, ['pinned: buy milk']);
    expect(mismatches, isEmpty);
    expect(host.registry.mismatches, isEmpty);
    await b.close();
  });

  test('the host sees what one guest led the other to do', () async {
    await loadInMemory(host, 'notes', startNotes);
    final (p, b) = await board();
    await b.pin('call ann');
    await p.flush();
    await settle();
    final why = host.registry.explain('notes.all');
    expect(why.change!.cause.by, Who.widlet('notes').child('book'));
    expect(why.trail.first.command, 'notes.add');
    expect(why.trail.first.cause.by, Who.widlet('board'));
    await b.close();
  });

  test(
    'a guest of another version is told, every difference at once',
    () async {
      // The notes guest as it was before: `notes.add` took a shorter text,
      // and its notes were texts alone.
      await loadInMemory(host, 'notes', (e) async {
        final p = await RemoteParticipant.over(e);
        p.defineCommand(
          CommandDescriptor(
            'notes.add',
            params: const ObjectType({'text': Field(TextType(maxLength: 100))}),
            callers: Who.callers,
          ),
          (_) => null,
        );
        p.defineState(
          StateDescriptor('notes.all', type: const ListType(TextType())),
        );
        await p.flush();
        return p;
      });
      final (p, b) = await board();
      await p.settle();
      await settle();
      expect(mismatches['notes.add'], [
        'params.fields.text.type.maxLength: was 200, is 100',
      ]);
      expect(mismatches['notes.all'], ['type.item.type: was object, is text']);
      expect(NotesClient(p).mismatches.keys, {'notes.add', 'notes.all'});
      expect(
        {
          for (final m in host.registry.mismatches)
            if (m.by == Who.widlet('board'))
              m.word: [for (final b in m.breaks) '$b'],
        },
        mismatches,
        reason: 'the host is told it too, as the board tells it',
      );
      await b.close();
    },
  );

  test('a guest that goes takes its words; one that comes again brings '
      'them, in any order', () async {
    final (p, b) = await board();
    expect(p.status('notes.add'), const WordMissing());
    final notes = await loadInMemory(host, 'notes', startNotes);
    await p.settle();
    expect(NotesClient(p).status(NotesCommand.add), const WordReady());
    host.unload('notes');
    await settle();
    expect(p.status('notes.add'), const WordMissing());
    await notes.close();
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
      () => p.state(NotesState.all).define(),
      throwsA(isA<NotPermitted>()),
    );
    await b.close();
  });
}
