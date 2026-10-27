import 'package:parlance/schema.dart';
import 'package:test/test.dart';

import 'fixtures/board.dart';

const me = Principal('board');
const ann = Principal('reader', 'ann');
const anyone = Callers({'*': Access.allow});

final class Pinboard extends BoardOwner {
  final Map<String, Note> up = {};
  final List<int> expiries = [];

  @override
  void defineMore(IParticipant p) {
    trackKind('note', () => [for (final id in up.keys) EntityRef(id)]);
  }

  @override
  void sync() {}

  @override
  ({String id}) put(CommandCallOf<BoardPut> call) {
    final id = call.params.id ?? 'n${up.length + 1}';
    up[id] = call.params.note;
    notes.set(call.params.note, key: id, cause: call.inReply);
    return (id: id);
  }

  @override
  void expire(CommandCallOf<BoardExpire> call) => expiries.add(call.params.ms);

  @override
  void count(CommandCallOf<BoardCount> call) {}

  @override
  void pin(CommandCallOf<BoardPin> call) {}
}

/// What a vocabulary says beyond `Player`'s: records of named fields as
/// values, params, answers and payloads, their fields annotated in the
/// typedef; any value; a duration; a param named otherwise in JSON; a word
/// named as its namespace; an open fact.
void main() {
  late Registry r;
  late IParticipant p;
  late Pinboard board;
  setUp(() {
    r = Registry(onError: (e, st) => throw e);
    p = r.participant(
      me,
      vocabularies: [boardWords],
      access: const WordAccess(call: anyone),
    );
    board = Pinboard();
    p.attach({'board': board});
  });
  tearDown(() => r.dispose());

  test('a record is an object of its fields, in the order the typedef says '
      'them, each as annotated there', () {
    final type = r.stateDescriptor('note')!.type.toJson();
    expect((type['fields']! as Map).keys, [
      'level',
      'text',
      'tags',
      'by',
      'action',
    ]);
    expect(type, {
      'type': 'object',
      'fields': {
        'level': {
          'type': {
            'type': 'enum',
            'values': ['info', 'warning'],
          },
        },
        'text': {
          'type': {'type': 'text', 'maxLength': 200},
          'description': 'What it says.',
        },
        'tags': {
          'type': {
            'type': 'list',
            'item': {'type': 'text'},
          },
          'optional': true,
          'default': <Object?>[],
        },
        'by': {
          'type': {'type': 'text'},
          'optional': true,
        },
        'action': {
          'type': {
            'type': 'object',
            'fields': {
              'call': {
                'type': {'type': 'text'},
              },
              'params': {
                'type': {
                  'type': 'map',
                  'value': {'type': 'any'},
                },
                'optional': true,
                'default': <String, Object?>{},
              },
            },
          },
          'optional': true,
        },
      },
    });
  });

  test('a record goes in and out as JSON, its fields by their JSON names, '
      'defaults filled', () async {
    final done = await r.call('note.put', {
      'note': {
        'level': 'warning',
        'text': 'Hi',
        'by': 'Ann',
        'action': {'call': 'note.expire'},
      },
    }, by: ann);
    expect(done.ok, isTrue, reason: '$done');
    expect((done as CallDone).value, {'id': 'n1'});
    final note = board.up['n1']!;
    expect(note.author, 'Ann');
    expect(note.tags, isEmpty);
    expect(note.action!.params, isEmpty);
    expect(r.read('note', key: 'n1'), {
      'level': 'warning',
      'text': 'Hi',
      'tags': <Object?>[],
      'by': 'Ann',
      'action': {'call': 'note.expire', 'params': <String, Object?>{}},
    });
    expect(BoardClient(LocalView(r, by: ann)).notesOf('n1')!.author, 'Ann');
  });

  test('a word named as its namespace, any value, a duration by its JSON '
      'name', () async {
    expect(BoardState.notes.name, 'note');
    board.anything.set({'a': 1});
    expect(r.read('note.anything'), {'a': 1});
    board.anything.set(null);
    expect(r.read('note.anything'), isNull);
    expect(r.commandDescriptor('note.expire')!.params.toJson()['fields'], {
      'id': {
        'type': {'type': 'ref', 'kind': 'note'},
      },
      'in': {
        'type': {'type': 'duration', 'max': 60000},
      },
    });
    await r.call('note.put', {
      'note': {'level': 'info', 'text': 'x'},
    }, by: ann);
    final done = await r.call('note.expire', {'id': 'n1', 'in': 500}, by: ann);
    expect(done.ok, isTrue, reason: '$done');
    expect(board.expiries, [500]);
    final long = await r.call('note.expire', {
      'id': 'n1',
      'in': 60001,
    }, by: ann);
    expect((long as CallRefused).code, Refusal.invalidParams);
  });

  test('a param one may leave out is optional, one that must be said but '
      'may be null is nullable', () {
    final put =
        r.commandDescriptor('note.put')!.params.toJson()['fields']! as Map;
    expect(put['id'], {
      'type': {'type': 'text'},
      'optional': true,
      'description': 'Its id; else a new one.',
    });
    final count = r.commandDescriptor('note.count')!.params.toJson();
    expect(count['fields'], {
      'readers': {
        'type': {
          'type': 'nullable',
          'of': {'type': 'int'},
        },
      },
    });
  });

  test('a list said of a kind names entities of it', () {
    expect(r.commandDescriptor('note.pin')!.params.toJson()['fields'], {
      'ids': {
        'type': {
          'type': 'list',
          'item': {'type': 'ref', 'kind': 'note'},
          'maxItems': 3,
        },
      },
    });
  });

  test('an open fact is said by others too', () {
    expect(r.factDescriptor('note.seen')!.open, isTrue);
    board.seen((
      level: Level.info,
      text: 'seen',
      tags: const [],
      author: null,
      action: null,
    ));
    expect(r.recent('note.seen').single.payload, {
      'level': 'info',
      'text': 'seen',
      'tags': <Object?>[],
    });
  });
}
