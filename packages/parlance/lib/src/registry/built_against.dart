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
    final breaks = live == null
        ? const <WordBreak>[]
        : entryBreaks(built!.schema, schemaOfDescriptor(live));
    final key = (by, word);
    final was = _mismatched[key];
    if (breaks.isEmpty) {
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
