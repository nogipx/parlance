// Internal to the library: what these files show is not a promise
// Documented surface lives in schema.dart and app.dart.
// ignore_for_file: public_member_api_docs
import 'dart:async';
import 'dart:collection';
import 'dart:developer' as developer;

import 'package:rpc_dart/logger.dart';

import '../core/core.dart';
import 'cause.dart';
import 'compat.dart';
import 'descriptors.dart';
import 'messages.dart';

/// What each principal's code was built against, and where the words as
/// they are now break it (SPEC §6.9, §25): the registry's diagnostics of
/// compatibility. Nothing waits on it, nothing is refused by it; the
/// registry tells it whenever a word comes, goes or is defined again.
final class BuiltAgainst {
  BuiltAgainst({
    required Descriptor? Function(String word) descriptorOf,
    required Map<String, String> aliases,
    required LogScope catalogLog,
    required LogScope callLog,
    required bool traced,
  }) : _descriptorOf = descriptorOf,
       _aliases = aliases,
       _catalogLog = catalogLog,
       _callLog = callLog,
       _traced = traced;

  /// How many words one principal is told built against at most: past
  /// them a peer's made-up names keep nothing.
  static const perPrincipal = 1024;

  /// How many schemas it knows by fingerprint at most, the least recently
  /// told going first (SPEC §25.4).
  static const knownSchemas = 4096;

  final Descriptor? Function(String word) _descriptorOf;

  /// The registry's old names of words, each to the word's name now.
  final Map<String, String> _aliases;
  final LogScope _catalogLog;
  final LogScope _callLog;
  final bool _traced;

  /// The schemas told it, by fingerprint: a part tells a fingerprint
  /// first, and its schema only when it is not known here.
  final LinkedHashMap<String, Object?> _known = LinkedHashMap();

  /// The words each principal's code was built against, by name as it
  /// names them, each as a schema entry (SPEC §6.9).
  final Map<Principal, Map<String, _Built>> _built = {};

  /// Who was built against each name.
  final Map<String, Set<Principal>> _builtBy = {};

  /// Each word a principal was built against that breaks it now, and
  /// where, in the order found.
  final Map<(Principal, String), List<WordBreak>> _mismatched = {};
  final StreamController<Mismatch> _mismatches = StreamController.broadcast();

  /// The breaks a value written, said or answered met (SPEC §25.2): an
  /// enum value or a variant a principal's code does not know, a field it
  /// needs left out; by path, certain from then on, where they were only
  /// possible.
  final Map<(Principal, String), Set<String>> _met = {};

  /// The mismatches that a value may meet, by the word's name now: those
  /// with a break in what the code reads that a value may never meet.
  final Map<String, Set<(Principal, String)>> _open = {};

  /// The name each mismatch of [_open] is kept under: an old name may
  /// stand for another word by now.
  final Map<(Principal, String), String> _openAt = {};

  /// Every word a principal's code was built against that is defined
  /// otherwise now, saying where it breaks.
  List<Mismatch> get mismatches => [
    for (final MapEntry(key: (by, word), value: breaks) in _mismatched.entries)
      Mismatch(by, word, breaks, from: _built[by]?[word]?.from),
  ];

  /// A [Mismatch] whenever one is found, breaks otherwise, or ends: then
  /// its breaks are empty.
  Stream<Mismatch> get changes => _mismatches.stream;

  /// [by]'s code was built against [schemas], each word's schema entry by
  /// name: judged now, and whenever one is defined again, until the handle
  /// is disposed. A word told again is held to the newest; one past
  /// [perPrincipal] is not kept.
  IHandle tell(Principal by, Map<String, Object?> schemas, {String? from}) {
    final mine = _built.putIfAbsent(by, () => {});
    final told = <String>[];
    for (final MapEntry(key: word, value: schema) in schemas.entries) {
      final had = mine[word];
      if (had == null && mine.length >= perPrincipal) continue;
      _know(schema);
      if (had != null &&
          had.from == from &&
          fingerprintOf(had.schema) == fingerprintOf(schema)) {
        had.holders++;
      } else {
        mine[word] = _Built(schema, (had?.holders ?? 0) + 1, from);
      }
      (_builtBy[word] ??= {}).add(by);
      told.add(word);
      _judge(by, word);
    }
    if (mine.isEmpty) _built.remove(by);
    return Disposer(() {
      for (final word in told) {
        final b = _built[by]?[word];
        if (b == null || --b.holders > 0) continue;
        _built[by]!.remove(word);
        if (_built[by]!.isEmpty) _built.remove(by);
        if (_builtBy[word] case final who?) {
          who.remove(by);
          if (who.isEmpty) _builtBy.remove(word);
        }
        _judge(by, word);
      }
    });
  }

  /// The schema told it under [print], a fingerprint (SPEC §25.4); null
  /// when it knows none.
  Object? knownSchema(String print) {
    final schema = _known.remove(print);
    if (schema == null) return null;
    return _known[print] = schema;
  }

  void _know(Object? schema) {
    final print = fingerprintOf(schema);
    _known.remove(print);
    _known[print] = schema;
    if (_known.length > knownSchemas) _known.remove(_known.keys.first);
  }

  /// Word [name] came, went or was defined again: whoever was built
  /// against it, or an old name of it, judged again.
  void wordChanged(String name) {
    final names = [
      name,
      for (final MapEntry(:key, :value) in _aliases.entries)
        if (value == name) key,
    ];
    for (final n in names) {
      aliasChanged(n);
    }
  }

  /// Old name [alias] came, went or names another word: whoever was built
  /// against it judged again.
  void aliasChanged(String alias) {
    for (final by in [...?_builtBy[alias]]) {
      _judge(by, alias);
    }
  }

  /// Whether [word] as it is now breaks what [by] was built against.
  void _judge(Principal by, String word) {
    final built = _built[by]?[word];
    final live = built == null ? null : _descriptorOf(word);
    final key = (by, word);
    final met = _met[key] ?? const {};
    final breaks = live == null
        ? const <WordBreak>[]
        : [
            for (final b in entryBreaks(
              built!.schema,
              schemaOfDescriptor(live),
            ))
              b.certain || !met.contains(b.path)
                  ? b
                  : WordBreak(b.path, b.kind, b.was, b.now),
          ];
    _openFor(key, breaks);
    final was = _mismatched[key];
    if (breaks.isEmpty) {
      _met.remove(key);
      if (was == null) return;
      _mismatched.remove(key);
    } else {
      if (was != null && sameBreaks(was, breaks)) return;
      _mismatched[key] = breaks;
      _warn(by, word, breaks, built!.from);
    }
    if (!_mismatches.isClosed) {
      _mismatches.add(Mismatch(by, word, breaks, from: built?.from));
    }
  }

  /// Whether [key]'s mismatch is one a value may meet, kept in [_open].
  void _openFor((Principal, String) key, List<WordBreak> breaks) {
    if (_openAt.remove(key) case final was?) {
      final keys = _open[was]!..remove(key);
      if (keys.isEmpty) _open.remove(was);
    }
    if (!breaks.any(_mayMeet)) return;
    final name = _aliases[key.$2] ?? key.$2;
    (_open[name] ??= {}).add(key);
    _openAt[key] = name;
  }

  /// A break in what code reads that a value may never meet: an enum
  /// value or a variant it does not know, a field it needs that may be
  /// left out.
  static bool _mayMeet(WordBreak b) =>
      !b.certain &&
      (b.kind == BreakKind.value ||
          (b.kind == BreakKind.field && b.now == 'optional')) &&
      (b.path.startsWith('type.') || b.path.startsWith('returns.'));

  /// The values [t] wrote and said, each judged against the code of
  /// whoever was built against its word otherwise.
  void ticked(Tick t) {
    if (_open.isEmpty) return;
    for (final c in t.changes) {
      if (c.removed) continue;
      for (final key in [...?_open[c.state]]) {
        _meet(key, 'type', () => c.value);
      }
    }
    for (final f in t.facts) {
      for (final key in [...?_open[f.fact]]) {
        _meet(key, 'type', () => f.payload);
      }
    }
  }

  /// [by]'s call of [command] was answered [done]: judged against what
  /// [by]'s code reads of the answer.
  void answered(String command, Principal by, CallDone<Object?> done) {
    if (_open.isEmpty) return;
    for (final key in [...?_open[command]]) {
      if (key.$1 == by) _meet(key, 'returns', () => done.value);
    }
  }

  /// Whether [value], at [root] of [key]'s word (its type, or its answer),
  /// meets one of [key]'s breaks: an enum value or a variant its code does
  /// not know, a field it needs left out. Then that break is certain.
  void _meet((Principal, String) key, String root, Object? Function() value) {
    final breaks = _mismatched[key];
    final live = _descriptorOf(key.$2);
    if (breaks == null || live == null) return;
    final type = schemaOfDescriptor(live)[root];
    final met = _met[key] ?? const {};
    late final given = value();
    var found = false;
    for (final b in breaks) {
      if (!_mayMeet(b) || met.contains(b.path)) continue;
      final path = b.path.split('.');
      if (path.first != root) continue;
      final known = {if (b.was case final List<Object?> was) ...was};
      if (_meets(type, given, path, 1, known)) {
        (_met[key] ??= {}).add(b.path);
        found = true;
      }
    }
    if (found) _judge(key.$1, key.$2);
  }

  /// [params] of a call of [command] (as [takes] it) by [by], with what
  /// [by] was built against giving and the command no longer takes left
  /// out (SPEC §25.5), as Avro's reader skips a field it does not know:
  /// code built before a param went goes on calling. Only for one whose
  /// words are told otherwise (a [Mismatch] of [command]), and only params
  /// of the call itself; what it gave is not heard, and the mismatch still
  /// says so.
  Kept adapted(
    String command,
    CallableDescriptor takes,
    Kept params,
    Principal by,
  ) {
    final mine = _built[by];
    if (mine == null) return params;
    final name = mine.containsKey(command)
        ? command
        : _aliases.entries
              .where((a) => a.value == command && mine.containsKey(a.key))
              .firstOrNull
              ?.key;
    if (name == null || !_mismatched.containsKey((by, name))) return params;
    final built = mine[name]!.schema;
    final gave = ((built as Map?)?['params'] as Map?)?['fields'] as Map?;
    final json = params.json;
    if (gave == null || json is! Map) return params;
    final fields = takes.params.fields;
    final gone = [
      for (final k in json.keys)
        if (!fields.containsKey(k) && gave.containsKey(k)) k,
    ];
    if (gone.isEmpty) return params;
    if (_callLog.isEnabled(RpcLogLevel.info)) {
      _callLog.info(
        'params left out',
        data: {'command': command, 'by': by.selector, 'params': gone},
      );
    }
    return Kept.json({
      for (final MapEntry(:key, :value) in json.entries)
        if (!gone.contains(key)) key: value,
    });
  }

  /// Logs a mismatch found as a warning in `catalog`; with no log, while
  /// asserts run (in development), in the developer log.
  void _warn(Principal by, String word, List<WordBreak> breaks, String? from) {
    if (_catalogLog.isEnabled(RpcLogLevel.warning)) {
      _catalogLog.warning(
        'built against otherwise',
        data: {
          'by': by.selector,
          'word': word,
          'from': ?from,
          'breaks': [for (final b in breaks) '$b'],
        },
      );
      return;
    }
    if (_traced) return;
    assert(() {
      developer.log(
        '${by.selector} was built against $word'
        '${from == null ? '' : ' of $from'} otherwise: ${breaks.join('; ')}',
        name: 'parlance',
        level: 900,
      );
      return true;
    }());
  }

  Future<void> dispose() => _mismatches.close();
}

/// Whether [value], of [type], meets at [path] (from [i] on, a break's path
/// into a schema entry) what the break says: a value not among [known]
/// (an enum value, the tag of a variant), or a field left out.
bool _meets(
  Object? type,
  Object? value,
  List<String> path,
  int i,
  Set<Object?> known,
) {
  if (value == null || type is! Map) return false;
  if (type['type'] == 'nullable') {
    final next = i < path.length && path[i] == 'of' ? i + 1 : i;
    return _meets(type['of'], value, path, next, known);
  }
  if (i >= path.length) return false;
  switch (path[i]) {
    case 'values':
      return value is String && !known.contains(value);
    case 'variants':
      if (value is! Map) return false;
      final tag = value[type['key']];
      if (i + 1 == path.length) return tag != null && !known.contains(tag);
      if (tag != path[i + 1]) return false;
      return _meets(
        (type['variants'] as Map?)?[tag],
        value,
        path,
        i + 2,
        known,
      );
    case 'fields':
      if (value is! Map || i + 1 >= path.length) return false;
      // The field itself, one the code needs: met when it is not there.
      if (i + 2 == path.length) return value[path[i + 1]] == null;
      final field = (type['fields'] as Map?)?[path[i + 1]];
      return _meets(
        field is Map ? field['type'] : null,
        value[path[i + 1]],
        path,
        i + 3,
        known,
      );
    case 'item':
      return value is List &&
          value.any((v) => _meets(type['item'], v, path, i + 1, known));
    case 'value':
      return value is Map &&
          value.values.any((v) => _meets(type['value'], v, path, i + 1, known));
  }
  return false;
}

/// A word's schema entry a principal was built against, and how many of
/// its handles hold it.
final class _Built {
  _Built(this.schema, this.holders, this.from);
  final Object? schema;
  int holders;

  /// The words package it came from, as code says it (`notes_words
  /// 1.2.0`).
  final String? from;
}
