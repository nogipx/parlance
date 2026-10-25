import 'package:parlance/links.dart';
import 'package:parlance/registry.dart';
import 'package:test/test.dart';

import 'fixture.dart';

/// Who names a word: the links a change of it would set off, those that
/// read it, those that call it.
void main() {
  late LinksFixture f;
  setUp(() => f = LinksFixture());
  tearDown(() => f.links.dispose());

  test('each link that names a word, with how', () async {
    f.use([
      {
        'id': 'muted-says',
        'when': [
          {'state': 'audio.muted', 'becomes': true},
        ],
        'do': [
          {
            'call': 'test.say',
            'params': {'text': r'$state.studio.program'},
          },
        ],
      },
      {
        'id': 'raid-mutes',
        'when': [
          {'fact': 'platform.raid'},
        ],
        'only': [
          {'state': 'studio.program', 'is': 'main'},
        ],
        'do': [
          {'flip': 'audio.muted'},
        ],
      },
      {
        'id': 'hold',
        'while': [
          {'state': 'studio.program', 'is': 'break'},
        ],
        'hold': [
          {
            'call': 'audio.mute',
            'params': {'on': true},
          },
        ],
      },
    ]);
    expect(f.links.uses('audio.muted'), [
      (link: 'muted-says', how: 'trigger'),
      (link: 'raid-mutes', how: 'flip'),
    ]);
    expect(f.links.uses('studio.program').toSet(), {
      (link: 'muted-says', how: 'reads'),
      (link: 'raid-mutes', how: 'condition'),
      (link: 'hold', how: 'condition'),
    });
    expect(f.links.uses('audio.mute'), [(link: 'hold', how: 'holds')]);
    expect(f.links.uses('platform.raid'), [
      (link: 'raid-mutes', how: 'trigger'),
    ]);
    expect(f.links.uses('nobody.knows'), isEmpty);

    final r = await f.r.command(LinkWords.uses).call((
      word: 'audio.muted',
    ), by: user);
    expect((r as CallDone<LinkUses>).value.uses, hasLength(2));
  });
}
