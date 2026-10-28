import '../registry/cause.dart';
import '../registry/compat.dart';

/// What a participant across a connection tells its host it was built
/// against (SPEC §6.9, §25.4): each word once, by fingerprint, as an
/// Avro handshake tells a protocol by its hash; its schema only when the
/// host answers it does not know that fingerprint.
final class BuiltTold {
  /// By part (null: the participant itself), by word: the schema and the
  /// words package it came from.
  final Map<Principal?, Map<String, ({Object? schema, String? from})>> _told =
      {};

  /// The schemas each op told by fingerprint, for when the host asks.
  final Expando<Map<String, Object?>> _schemasOf = Expando();

  bool get isEmpty => _told.isEmpty;

  /// The op telling what of [schemas] it did not tell yet, as [as] and
  /// from [from]; none when it told all of it.
  List<Map<String, Object?>> tell(
    Map<String, Object?> schemas, {
    String? from,
    Principal? as,
  }) {
    final had = _told.putIfAbsent(as, () => {});
    bool same(String word, Object? schema) => switch (had[word]) {
      final h? =>
        h.from == from && fingerprintOf(h.schema) == fingerprintOf(schema),
      null => false,
    };
    final told = <String, Object?>{
      for (final MapEntry(key: word, value: schema) in schemas.entries)
        if (!same(word, schema)) word: schema,
    };
    if (told.isEmpty) return const [];
    for (final MapEntry(key: word, value: schema) in told.entries) {
      had[word] = (schema: schema, from: from);
    }
    return [_byPrint(told, from, as)];
  }

  Map<String, Object?> _byPrint(
    Map<String, Object?> schemas,
    String? from,
    Principal? as,
  ) {
    final op = <String, Object?>{
      'op': 'built',
      'prints': {
        for (final MapEntry(key: word, value: schema) in schemas.entries)
          word: fingerprintOf(schema),
      },
      'from': ?from,
      'as': ?as?.toJson(),
    };
    _schemasOf[op] = schemas;
    return op;
  }

  /// The op telling the schemas the host answered [op] it did not know;
  /// null for any other answer.
  Map<String, Object?>? answered(
    Map<String, Object?> op,
    Map<String, Object?> answer,
  ) {
    final unknown = answer['unknown'];
    final schemas = _schemasOf[op];
    if (unknown is! List || unknown.isEmpty || schemas == null) return null;
    return {
      'op': 'built',
      'words': {
        for (final word in unknown)
          if (schemas.containsKey(word)) '$word': schemas[word],
      },
      'from': ?op['from'],
      'as': ?op['as'],
    };
  }

  /// All it told, for a new session: by part and package.
  List<Map<String, Object?>> standing() => [
    for (final MapEntry(key: part, value: words) in _told.entries)
      for (final from in {for (final w in words.values) w.from})
        _byPrint(
          {
            for (final MapEntry(key: word, value: w) in words.entries)
              if (w.from == from) word: w.schema,
          },
          from,
          part,
        ),
  ];

  /// The ops letting go of all it told, and forgets it.
  List<Map<String, Object?>> forget() {
    final ops = [
      for (final part in _told.keys) {'op': 'unbuilt', 'as': ?part?.toJson()},
    ];
    _told.clear();
    return ops;
  }
}
