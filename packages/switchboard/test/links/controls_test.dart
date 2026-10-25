import 'package:switchboard/links.dart';
import 'package:switchboard/registry.dart';
import 'package:test/test.dart';

import 'fixture.dart';

/// Reactions someone can press, as controls: shown, lit, unavailable.
void main() {
  late LinksFixture f;
  String? blocked;
  setUp(() {
    f = LinksFixture();
    blocked = null;
    f.r.defineCommand(
      CommandDescriptor(
        'test.blocked',
        callers: const Callers({'*': Access.allow}),
      ),
      (_) {},
      available: () => blocked,
    );
    f.use([
      {
        'id': 'blocked',
        'when': [
          {'manual': <String, Object?>{}},
        ],
        'do': [
          {'call': 'test.blocked'},
        ],
      },
      {
        'id': 'mute',
        'when': [
          {
            'manual': {'label': 'Mute'},
          },
        ],
        'do': [
          {'flip': 'audio.muted'},
        ],
      },
      {
        'id': 'main',
        'when': [
          {
            'manual': {'label': 'Main'},
          },
        ],
        'do': [
          {
            'call': 'studio.show',
            'params': {'scene': 'main'},
          },
        ],
      },
      {
        'id': 'muted-look',
        'when': [
          {
            'manual': {
              'label': 'Said',
              'lit': {'state': 'audio.muted', 'is': true},
            },
          },
        ],
        'do': [
          {
            'call': 'test.say',
            'params': {'text': 'hi'},
          },
        ],
      },
      {
        'id': 'only-muted',
        'when': [
          {'manual': <String, Object?>{}},
        ],
        'only': [
          {'state': 'audio.muted', 'is': true},
        ],
        'do': <Object?>[],
      },
      {
        'id': 'not-pressable',
        'when': [
          {'fact': 'platform.raid'},
        ],
        'do': <Object?>[],
      },
    ]);
  });
  tearDown(() => f.links.dispose());

  test('controls are pressable reactions whose only holds, in order', () {
    expect(
      [for (final c in f.links.controls()) c.id],
      ['blocked', 'mute', 'main', 'muted-look'],
    );
    expect(f.links.controls()[1].look, {'label': 'Mute'});
  });

  test('lit follows a flip, what a call sets, or the look\'s condition', () {
    f.muted.set(false);
    f.program.set('break');
    Map<String, bool?> lit() => {
      for (final c in f.links.controls()) c.id: c.lit,
    };
    expect(lit(), {
      'blocked': null,
      'mute': false,
      'main': false,
      'muted-look': false,
    });
    f.muted.set(true);
    f.program.set('main');
    expect(lit(), {
      'blocked': null,
      'mute': true,
      'main': true,
      'muted-look': true,
      'only-muted': null,
    });
  });

  test('a control says why it cannot work now', () {
    Iterable<String?> why() => [
      for (final c in f.links.controls())
        if (c.id == 'blocked') c.unavailable,
    ];
    expect(why(), [null]);
    blocked = 'the mixer is off';
    expect(why(), ['the mixer is off']);
  });

  test('the controls are a state too, there for a client of the registry '
      'alone, and follow what their links read', () async {
    f.muted.set(false);
    await Future<void>.delayed(Duration.zero);
    List<ControlView> held() =>
        f.r.state(LinkWords.controls).read() ?? const [];
    expect([for (final c in held()) c.id], [
      'blocked',
      'mute',
      'main',
      'muted-look',
    ]);
    final mute = held()[1];
    expect((mute.id, mute.lit, mute.unavailable), ('mute', false, null));
    expect(mute.look, {'label': 'Mute'});
    f.muted.set(true);
    await Future<void>.delayed(Duration.zero);
    expect([for (final c in held()) c.id], contains('only-muted'));
    expect(held()[1].lit, isTrue);
  });

  test('a press answers when its run ended, or why not', () async {
    expect(await f.r.pressLink('main', by: user), isNull);
    expect(f.r.read('studio.program'), 'main');
    expect(await f.r.pressLink('not-pressable', by: user), 'not pressable');
    expect(await f.r.pressLink('gone', by: user), contains('no link gone'));
  });
}
