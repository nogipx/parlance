import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'descriptors.dart';
import 'json.dart';
import 'words.dart';

// Whether a word is what code was built against (SPEC §23.3, §6.5): one
// rule for a vocabulary's kept schema and for a word met at run time.

/// What [w] says of itself: its kind and its types, as a schema entry;
/// made once a word.
Map<String, Object?> schemaOfWord(IWord w) => _schemas[w] ??= _schemaOf(w);

final Expando<Map<String, Object?>> _schemas = Expando();

/// [words] by name, each as [schemaOfWord] says it.
Map<String, Object?> schemasOf(Iterable<IWord> words) => {
  for (final w in words) w.name: schemaOfWord(w),
};

Map<String, Object?> _schemaOf(IWord w) => switch (w) {
  IStateWord(:final shape, :final key) => {
    'is': 'state',
    'type': shape.type.toJson(),
    'key': ?key,
  },
  ICommandWord(:final params, :final returns) => {
    'is': 'command',
    'params': params.type.toJson(),
    if (returns != null) 'returns': returns.type.toJson(),
  },
  IQueryWord(:final params, :final returns) => {
    'is': 'query',
    'params': params.type.toJson(),
    'returns': returns.type.toJson(),
  },
  IFactWord(:final shape) => {'is': 'fact', 'type': shape.type.toJson()},
  _ => throw ArgumentError('${w.name} is no word of a kind parlance knows'),
};

/// [schema], a word's schema entry or a schema of words by name, as one
/// text saying only what the rule of §25.1 judges (SPEC §25.4): every
/// object's keys in order, what a type or a field says for people (its
/// descriptions) left out. Two schemas that say the same in another order
/// of keys (one that went over a wire) are one text.
String canonicalSchema(Object? schema) => jsonEncode(
  schema is Map && !schema.containsKey('is')
      ? {for (final k in _sorted(schema.keys)) k: _entry(schema[k])}
      : _entry(schema),
);

/// The fingerprint of [schema] (SPEC §25.4): the SHA-256 of
/// [canonicalSchema], in hex. One fingerprint is one schema, so a word told
/// by fingerprint is judged as told by its schema; two fingerprints may
/// still keep each other's promises, which only the rule says. Made once a
/// schema object.
String fingerprintOf(Object? schema) {
  if (schema is Map) return _prints[schema] ??= _print(schema);
  return _print(schema);
}

final Expando<String> _prints = Expando();

String _print(Object? schema) =>
    sha256.convert(utf8.encode(canonicalSchema(schema))).toString();

List<String> _sorted(Iterable<Object?> keys) =>
    [for (final k in keys) '$k']..sort();

/// What is not a type nor a field, its keys in order.
Object? _plain(Object? v) => switch (v) {
  Map() => {for (final k in _sorted(v.keys)) k: _plain(v[k])},
  List() => [for (final x in v) _plain(x)],
  _ => v,
};

Object? _entry(Object? e) {
  if (e is! Map) return _plain(e);
  return {
    for (final k in _sorted(e.keys))
      k: switch (k) {
        'type' || 'params' || 'returns' => _type(e[k]),
        _ => _plain(e[k]),
      },
  };
}

Object? _type(Object? t) {
  if (t is! Map) return _plain(t);
  return {
    for (final k in _sorted(t.keys))
      if (k != 'descriptions')
        k: switch (k) {
          'item' || 'value' || 'of' => _type(t[k]),
          'fields' => {
            for (final f in _sorted(_map(t[k]).keys)) f: _field(_map(t[k])[f]),
          },
          'variants' => {
            for (final v in _sorted(_map(t[k]).keys)) v: _type(_map(t[k])[v]),
          },
          _ => _plain(t[k]),
        },
  };
}

Object? _field(Object? f) {
  if (f is! Map) return _plain(f);
  return {
    for (final k in _sorted(f.keys))
      if (k != 'description') k: k == 'type' ? _type(f[k]) : _plain(f[k]),
  };
}

/// What a word defined in the registry says of itself, as a schema entry
/// of [schemaOfWord]'s form.
Map<String, Object?> schemaOfDescriptor(Descriptor d) => switch (d) {
  StateDescriptor(:final type, :final key) => {
    'is': 'state',
    'type': type.toJson(),
    'key': ?key,
  },
  CommandDescriptor(:final params, :final returns) => {
    'is': 'command',
    'params': params.toJson(),
    if (returns != null) 'returns': returns.toJson(),
  },
  QueryDescriptor(:final params, :final returns) => {
    'is': 'query',
    'params': params.toJson(),
    if (returns != null) 'returns': returns.toJson(),
  },
  FactDescriptor(:final type) => {'is': 'fact', 'type': type.toJson()},
};

/// What kind of promise a word met breaks (SPEC §25.1).
enum BreakKind {
  /// It is another kind of word (a state where a command was), or keyed
  /// otherwise.
  word,

  /// A value of one type where another was: no value passes both.
  type,

  /// A bound one side holds values to and the other does not: a value
  /// within one is outside the other.
  bound,

  /// A field one side needs and the other may not give, or one it gives
  /// that the other refuses.
  field,

  /// An enum value or a variant one side may say and the other does not
  /// know.
  value,
}

/// One place a word met breaks what code was built against it (SPEC
/// §25.1): where ([path], into its schema entry), what kind of promise,
/// what the code was built against ([was]) and what the word says now
/// ([now]). [certain]: every use of the word meets it (a type changed, a
/// field gone that is needed); else only some values do (a bound moved,
/// an enum value added, a field that may be left out), and a part may
/// never meet it.
final class WordBreak {
  const WordBreak(
    this.path,
    this.kind,
    this.was,
    this.now, {
    this.certain = true,
  });

  final String path;
  final BreakKind kind;
  final Object? was;
  final Object? now;
  final bool certain;

  Map<String, Object?> toJson() => {
    'path': path,
    'kind': kind.name,
    'was': was,
    'is': now,
    if (!certain) 'certain': false,
  };

  @override
  bool operator ==(Object other) =>
      other is WordBreak &&
      other.path == path &&
      other.kind == kind &&
      other.certain == certain &&
      jsonEquals(other.was, was) &&
      jsonEquals(other.now, now);

  @override
  int get hashCode => Object.hash(path, kind, certain);

  @override
  String toString() => '$path: was ${_said(was)}, is ${_said(now)}';
}

String _said(Object? v) => v == null ? 'nothing' : '$v';

/// Whether [a] and [b] say the same breaks, in the same order.
bool sameBreaks(List<WordBreak> a, List<WordBreak> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Whether [now] keeps every promise [before] made (SPEC §25.1): code
/// built against [before] works with [now].
bool keepsPromises(Object? before, Object? now) =>
    entryBreaks(before, now).isEmpty;

/// What of [word] the code was built against does [live], the word met,
/// break: empty when it keeps every promise. Judged once a pair: a
/// status asked again answers at once.
List<WordBreak> wordBreaks(IWord word, Descriptor live) =>
    (_judged[live] ??= Map.identity())[word] ??= entryBreaks(
      schemaOfWord(word),
      schemaOfDescriptor(live),
    );

final Expando<Map<IWord, List<WordBreak>>> _judged = Expando();

/// The cache above is judged per live descriptor and reclaims with it:
/// a word defined again does not pile entries up, and while a descriptor
/// lives it holds one entry per word consulted, the memoization it is
/// for.

/// What of [built], a word's schema entry as code was built against it,
/// [live], the entry of the word as defined, breaks (SPEC §25.1), every
/// place at once.
///
/// Judged as the data goes: what the code reads (a state's and a fact's
/// values, an answer) it must be able to read as the word gives it now;
/// what it gives (a command's or a query's params) the word must take
/// now. So a reader is held to what a writer may give: a field added to
/// what code reads breaks nothing (it is skipped), one taken from what it
/// gives does (the registry refuses a field it does not know), and an
/// integer reads where a number is read.
List<WordBreak> entryBreaks(Object? built, Object? live) {
  final b = _map(built);
  final l = _map(live);
  if (b['is'] != l['is']) {
    return [WordBreak('is', BreakKind.word, b['is'], l['is'])];
  }
  final out = <WordBreak>[];
  if (b['key'] != l['key']) {
    out.add(WordBreak('key', BreakKind.word, b['key'], l['key']));
  }
  switch (b['is']) {
    case 'state' || 'fact':
      _Judge(out, builtReads: true).read('type', b['type'], l['type']);
    case 'command' || 'query':
      _Judge(out, builtReads: false).read('params', l['params'], b['params']);
      if (b['returns'] case final r?) {
        if (l['returns'] case final now?) {
          _Judge(out, builtReads: true).read('returns', r, now);
        } else if (_map(r)['type'] != 'nullable' && _map(r)['type'] != 'any') {
          out.add(WordBreak('returns', BreakKind.type, _map(r)['type'], null));
        }
      }
  }
  return out;
}

Map<Object?, Object?> _map(Object? v) => v is Map ? v : const {};

/// One walk of a reader's type and a writer's: what the writer may give
/// that the reader cannot take, said as code built against the word
/// ([builtReads]: the reader) and the word now see it.
final class _Judge {
  _Judge(this.out, {required this.builtReads});

  final List<WordBreak> out;

  /// Whether the code built against the word reads (it skips fields it
  /// does not know), or gives (the registry reads it, and refuses them).
  final bool builtReads;

  /// A break at [path], [r] the reader's side and [w] the writer's.
  void _add(
    String path,
    BreakKind kind,
    Object? r,
    Object? w, {
    bool certain = true,
  }) => out.add(
    WordBreak(
      path,
      kind,
      builtReads ? r : w,
      builtReads ? w : r,
      certain: certain,
    ),
  );

  void read(String at, Object? reader, Object? writer) {
    final r = _map(reader);
    final w = _map(writer);
    final rt = r['type'];
    final wt = w['type'];
    if (rt == 'any') return;
    if (wt == 'nullable') {
      if (rt == 'nullable') return read('$at.of', r['of'], w['of']);
      return _add('$at.type', BreakKind.type, rt, wt);
    }
    if (rt == 'nullable') return read(at, r['of'], w);
    if (rt != wt) {
      // What was an int reads as a duration still (millis); a moment is
      // a text now, and reading old millis data is told as a break.
      final promoted = rt == 'num' && (wt == 'int' || wt == 'duration') ||
          rt == 'int' && wt == 'duration';
      if (!promoted) return _add('$at.type', BreakKind.type, rt, wt);
    }
    switch (rt) {
      case 'int' || 'num' || 'duration':
        _bound(at, 'min', _min(r), _min(w), atLeast: true);
        _bound(at, 'max', r['max'], w['max']);
      case 'text':
        _bound(at, 'maxLength', r['maxLength'], w['maxLength']);
      case 'enum':
        // Code that reads it takes a value it does not know for its
        // fallback; the registry, reading what code gives, refuses one.
        if (builtReads && r['unknown'] != null) return;
        final known = {...?(r['values'] as List?)};
        if ((w['values'] as List? ?? const []).any((v) => !known.contains(v))) {
          _add(
            '$at.values',
            BreakKind.value,
            r['values'],
            w['values'],
            certain: false,
          );
        }
      case 'ref':
        if (r['kind'] != w['kind']) {
          _add('$at.kind', BreakKind.type, r['kind'], w['kind']);
        }
      case 'custom':
        if (r['name'] != w['name']) {
          _add('$at.name', BreakKind.type, r['name'], w['name']);
        }
      case 'list':
        _bound(at, 'maxItems', r['maxItems'], w['maxItems']);
        read('$at.item', r['item'], w['item']);
      case 'map':
        _bound(at, 'maxEntries', r['maxEntries'], w['maxEntries']);
        read('$at.value', r['value'], w['value']);
      case 'object':
        _fields(at, _map(r['fields']), _map(w['fields']));
      case 'oneOf':
        if (r['key'] != w['key']) {
          return _add('$at.key', BreakKind.type, r['key'], w['key']);
        }
        final rv = _map(r['variants']);
        final wv = _map(w['variants']);
        if (wv.keys.any((v) => !rv.containsKey(v)) &&
            !(builtReads && r['unknown'] == true)) {
          _add(
            '$at.variants',
            BreakKind.value,
            rv.keys.toList(),
            wv.keys.toList(),
            certain: false,
          );
        }
        for (final v in wv.keys) {
          if (rv[v] case final variant?) {
            _fields(
              '$at.variants.$v',
              _map(_map(variant)['fields']),
              _map(_map(wv[v])['fields']),
            );
          }
        }
    }
  }

  /// A duration is never below zero.
  static Object? _min(Map<Object?, Object?> t) =>
      t['min'] ?? (t['type'] == 'duration' ? 0 : null);

  /// The reader's bound [name] holds every value the writer's lets.
  void _bound(
    String at,
    String name,
    Object? r,
    Object? w, {
    bool atLeast = false,
  }) {
    if (r is! num) return;
    final within = w is num && (atLeast ? w >= r : w <= r);
    if (!within) {
      _add('$at.$name', BreakKind.bound, r, w, certain: false);
    }
  }

  static String? _presence(Object? f) => switch (f) {
    null => null,
    final Map<Object?, Object?> m
        when m['optional'] == true || m['default'] != null =>
      'optional',
    _ => 'required',
  };

  void _fields(
    String at,
    Map<Object?, Object?> reader,
    Map<Object?, Object?> writer,
  ) {
    for (final MapEntry(key: k, value: rf) in reader.entries) {
      final wf = writer[k];
      final need = _presence(rf) == 'required';
      if (wf == null) {
        if (need) _add('$at.fields.$k', BreakKind.field, 'required', null);
        continue;
      }
      // A field the writer may leave out the reader cannot do without;
      // one with a default the registry gives, written or not.
      final mayLack =
          _presence(wf) == 'optional' && _map(wf)['default'] == null;
      if (need && mayLack) {
        _add(
          '$at.fields.$k',
          BreakKind.field,
          'required',
          'optional',
          certain: false,
        );
      }
      read('$at.fields.$k.type', _map(rf)['type'], _map(wf)['type']);
    }
    // Code reading skips a field it does not know; the registry refuses
    // one it is given.
    if (builtReads) return;
    for (final MapEntry(key: k, value: wf) in writer.entries) {
      if (reader.containsKey(k)) continue;
      _add(
        '$at.fields.$k',
        BreakKind.field,
        null,
        _presence(wf),
        certain: _presence(wf) == 'required',
      );
    }
  }
}
