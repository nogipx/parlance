import 'package:parlance/registry.dart';
import 'package:test/test.dart';

/// A shape holds a Dart value to the rule its type holds the value's JSON
/// to (SPEC §18): what [Shape.check] keeps is what the type keeps of the
/// JSON, refused where the JSON is refused, with the same words at the same
/// path; [Shape.equals] is the JSON's equality and [Shape.weigh] its
/// weight. So a value written in this process and one come as JSON are
/// held to one rule.
final class _Ctx implements ITypeContext {
  @override
  bool hasKind(String kind) => kind == 'scene';

  @override
  bool hasEntity(String kind, String id) => kind == 'scene' && id == 'main';

  @override
  String? checkCustom(String name, Object? value) =>
      value is String && value.startsWith('#') ? null : 'not a color';
}

enum Mood { calm, loud }

typedef Track = ({String title, int volume, Mood mood, List<String> tags});

Map<String, Object?> _trackTo(Track t) => {
  'title': t.title,
  'volume': t.volume,
  'mood': t.mood,
  'tags': t.tags,
};
Track _trackFrom(Map<String, Object?> m) => (
  title: m['title']! as String,
  volume: m['volume']! as int,
  mood: m['mood']! as Mood,
  tags: m['tags']! as List<String>,
);

const track = RecordShape<Track>(
  {
    'title': Part(Plain(TextType(maxLength: 8))),
    'volume': Part(Plain(IntType(min: 0, max: 100))),
    'mood': Part(EnumShape(Mood.values)),
    'tags': Part(ListShape(Plain(TextType()), maxItems: 3)),
  },
  to: _trackTo,
  from: _trackFrom,
);

/// Fields that may be left out, one with a default, one that may be null,
/// one that must be there, and a ref.
typedef Cue = ({String? scene, String? note, int? fade, String? label});

Map<String, Object?> _cueTo(Cue c) => {
  'scene': c.scene,
  'note': c.note,
  'fade': c.fade,
  'label': c.label,
};
Cue _cueFrom(Map<String, Object?> m) => (
  scene: m['scene'] as String?,
  note: m['note'] as String?,
  fade: m['fade'] as int?,
  label: m['label'] as String?,
);

const cue = RecordShape<Cue>(
  {
    'scene': Part(Plain(RefType('scene'))),
    'note': Part(Nullable(Plain(TextType()))),
    'fade': Part(Plain(IntType(max: 500)), defaultValue: 250),
    'label': Part(Plain(TextType()), optional: true),
  },
  to: _cueTo,
  from: _cueFrom,
);

sealed class Shot {}

final class Wide extends Shot {
  Wide(this.lens);
  final int lens;
}

final class Close extends Shot {
  Close(this.who);
  final String who;
}

final shot = UnionShape<Shot>(
  'kind',
  {
    'wide': RecordShape<Shot>(
      const {'lens': Part(Plain(IntType(min: 10)))},
      to: (s) => {'lens': (s as Wide).lens},
      from: (m) => Wide(m['lens']! as int),
    ),
    'close': RecordShape<Shot>(
      const {'who': Part(Plain(TextType()))},
      to: (s) => {'who': (s as Close).who},
      from: (m) => Close(m['who']! as String),
    ),
  },
  tagOf: (s) => switch (s) {
    Wide() => 'wide',
    Close() => 'close',
  },
);

const playlist = ListShape(track, maxItems: 2);
const levels = MapShape(Plain(IntType(min: 0)), maxEntries: 2);
const color = Plain<Object?>(CustomType('color'));
const anyJson = JsonValue(AnyType());

Track t(
  String title, {
  int volume = 50,
  Mood mood = Mood.calm,
  List<String> tags = const [],
}) => (title: title, volume: volume, mood: mood, tags: tags);

void main() {
  final ctx = _Ctx();

  /// What the type does to [v]'s JSON: the JSON kept, or the refusal.
  Object? byJson<T>(Shape<T> s, T v) {
    try {
      return freezeJson(s.type.check(s.toJson(v), ctx));
    } on TypeMismatch catch (e) {
      return e;
    }
  }

  /// What the shape does to [v]: the JSON of what it keeps, or the refusal.
  Object? byShape<T>(Shape<T> s, T v) {
    try {
      return s.toJson(s.check(v, ctx));
    } on TypeMismatch catch (e) {
      return e;
    }
  }

  /// [v] is held by [s] as its JSON is held by its type.
  void same<T>(Shape<T> s, T v) {
    final json = byJson(s, v);
    final dart = byShape(s, v);
    if (json is TypeMismatch || dart is TypeMismatch) {
      expect('$dart', '$json', reason: 'refused alike: $v');
      expect(dart, isA<TypeMismatch>());
    } else {
      expect(jsonEquals(dart, json), isTrue, reason: '$dart vs $json');
      expect(s.weigh(s.check(v, ctx)), jsonWeight(json), reason: 'weight');
    }
  }

  /// [s] holds [a] and [b] equal exactly when their JSON is.
  void equalAlike<T>(Shape<T> s, T a, T b) => expect(
    s.equals(a, b),
    jsonEquals(s.toJson(a), s.toJson(b)),
    reason: '$a, $b',
  );

  test('a record passes and is refused as its JSON is', () {
    same(track, t('song', tags: ['a']));
    same(track, t('much too long'));
    same(track, t('song', volume: 101));
    same(track, t('song', tags: ['a', 'b', 'c', 'd']));
    same(track, t('song', mood: Mood.loud));
  });

  test('left-out fields: defaults, nulls, missing, refs', () {
    same(cue, (scene: 'main', note: null, fade: null, label: null));
    same(cue, (scene: 'main', note: 'hi', fade: 100, label: 'x'));
    same(cue, (scene: 'side', note: null, fade: 1, label: null));
    same(cue, (scene: null, note: null, fade: 1, label: null));
    same(cue, (scene: 'main', note: null, fade: 900, label: null));
    final kept = cue.check(
      (scene: 'main', note: null, fade: null, label: null),
      ctx,
    );
    expect(kept.fade, 250, reason: 'the default is given');
  });

  test('lists, maps, unions, custom types and plain JSON', () {
    same(playlist, [t('a'), t('b')]);
    same(playlist, [t('a'), t('b'), t('c')]);
    same(playlist, [t('a'), t('b', volume: -1)]);
    same(levels, {'mic': 3, 'desk': 0});
    same(levels, {'mic': -3});
    same(levels, {'a': 1, 'b': 2, 'c': 3});
    same(shot, Wide(35));
    same(shot, Wide(5));
    same(shot, Close('ann'));
    same(color, '#fff');
    same(color, 'red');
    same(anyJson, {
      'a': [1, 2],
    });
  });

  test('equal exactly where the JSON is', () {
    equalAlike(track, t('a', tags: ['x']), t('a', tags: ['x']));
    equalAlike(track, t('a'), t('a', volume: 51));
    equalAlike(playlist, [t('a')], [t('a')]);
    equalAlike(playlist, [t('a')], [t('a'), t('b')]);
    equalAlike(levels, {'mic': 1}, {'mic': 1});
    equalAlike(levels, {'mic': 1}, {'desk': 1});
    equalAlike(shot, Wide(35), Wide(35));
    equalAlike(shot, Wide(35), Close('ann'));
    equalAlike(cue, (
      scene: 'main',
      note: null,
      fade: 1,
      label: null,
    ), (scene: 'main', note: null, fade: 1, label: null));
  });

  test('what is kept cannot change: its lists are its own', () {
    final tags = ['a'];
    final kept = track.check(t('song', tags: tags), ctx);
    tags.add('b');
    expect(kept.tags, ['a'], reason: 'the writer keeps no hold on it');
    expect(() => kept.tags.add('c'), throwsUnsupportedError);
    final list = playlist.check([t('a')], ctx);
    expect(() => list.add(t('b')), throwsUnsupportedError);
    final map = levels.check({'mic': 1}, ctx);
    expect(() => map['desk'] = 2, throwsUnsupportedError);
  });

  test('a value kept already is kept as it is, nothing copied', () {
    final kept = track.check(t('song', tags: ['a']), ctx);
    expect(identical(track.check(kept, ctx), kept), isTrue);
    final list = playlist.check([kept], ctx);
    expect(identical(playlist.check(list, ctx), list), isTrue);
    final map = levels.check({'mic': 1}, ctx);
    expect(identical(levels.check(map, ctx), map), isTrue);
  });

  test('a class that serializes itself is kept as its JSON only', () {
    final shape = JsonShape<({String id})>(
      (m) => (id: m['id']! as String),
      (v) => {'id': v.id},
      type: const ObjectType({'id': Field(TextType())}),
    );
    expect(shape.keptAsIs, isFalse);
    expect(track.keptAsIs, isTrue);
    expect(const ListShape(Plain(TextType())).keptAsIs, isTrue);
    expect(ListShape(shape).keptAsIs, isFalse);
  });
}
