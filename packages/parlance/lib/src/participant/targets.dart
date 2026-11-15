part of 'participant.dart';

/// One published word, with its exact address and the caller's current status.
final class PublishedWord {
  /// A catalog entry; [descriptor] retains its portable vocabulary name.
  const PublishedWord(this.address, this.descriptor, this.status);

  /// Its exact publication address.
  final WordAddress address;

  /// Its contract, independent of the publishing instance.
  final Descriptor descriptor;

  /// Access and availability for the requesting participant.
  final WordStatus status;

  /// A catalog representation for tools.
  Map<String, Object?> toJson() => {
    ...descriptor.toJson(),
    'address': address.toString(),
    'target': address.target.toJson(),
    'status': switch (status) {
      WordReady() => 'ready',
      WordMissing() => 'missing',
      WordNotPermitted() => 'notPermitted',
      WordUnavailable() => 'unavailable',
      WordMismatch() => 'mismatch',
    },
    'why': ?status.why,
    if (status case WordMismatch(:final breaks))
      'breaks': [for (final b in breaks) b.toJson()],
  };
}

/// A named group of words actually published by one target.
/// This is a catalog group, not a declaration of the complete contract.
final class PublishedVocabulary {
  /// Its portable name and the matching, currently published words.
  PublishedVocabulary(this.name, Iterable<PublishedWord> words)
    : words = List.unmodifiable(words);

  /// The vocabulary name, such as `house`.
  final String name;

  /// Actual matching words; declarations without publications are absent.
  final List<PublishedWord> words;

  /// A catalog representation for tools.
  Map<String, Object?> toJson() => {
    'name': name,
    'words': [for (final w in words) w.toJson()],
  };
}

/// An instance that actually publishes words matching a discovery request.
final class WordTarget {
  /// A target and its matching vocabularies of published words.
  WordTarget(this.principal, Iterable<PublishedVocabulary> vocabularies)
    : vocabularies = List.unmodifiable(vocabularies);

  /// The exact whole principal; an ACL selector is never used for routing.
  final Principal principal;

  /// Named groups of actual words, each word with its own access status.
  final List<PublishedVocabulary> vocabularies;

  /// A catalog representation for tools.
  Map<String, Object?> toJson() => {
    'principal': principal.toJson(),
    'vocabularies': [for (final v in vocabularies) v.toJson()],
  };
}

void _checkTargetNames(String? vocabulary, String? word) {
  if (vocabulary != null) checkVocabularyName(vocabulary);
  if (word != null) {
    checkWordName(word, 'word');
    if (word.contains('/')) {
      throw ArgumentError.value(word, 'word', 'use a portable word name');
    }
  }
}

/// Discovers publications without selecting or reserving a dependency.
extension TargetDiscovery on IParticipant {
  /// Targets of a vocabulary name (`house`) or portable word name
  /// (`house.set_light`), grouped by vocabulary, or all targets when unfiltered.
  /// Both filters intersect when supplied together. Granted but unpublished
  /// vocabularies are absent; denied words stay visibly denied. Typed clients
  /// check compatibility against their own contract separately.
  Future<List<WordTarget>> targets({String? vocabulary, String? word}) async {
    _checkTargetNames(vocabulary, word);
    if (!raw.synced) return const [];
    final catalog = await raw.describe();
    final entries = <String, Descriptor>{
      for (final json in catalog['descriptors'] as List? ?? const [])
        if (Descriptor.fromJson(json) case final d) d.name: d,
    };
    // An alias is a publication of the same target, with its own address.
    for (final alias in (catalog['aliases'] as Map? ?? const {}).entries) {
      final publication = entries[alias.value];
      if (publication != null) {
        entries[alias.key as String] = Descriptor.fromJson({
          ...publication.toJson(),
          'name': alias.key,
        });
      }
    }
    final byTarget = <Principal, Map<String, List<PublishedWord>>>{};
    final unavailable = catalog['unavailable'] as Map? ?? const {};
    for (final entry in entries.values) {
      final address = WordAddress.parse(entry.name);
      final name = address.word.split('.').first;
      if (vocabulary != null && name != vocabulary) {
        continue;
      }
      if (word != null && address.word != word) {
        continue;
      }
      final portable = Descriptor.fromJson({
        ...entry.toJson(),
        'name': address.word,
      });
      final access = switch (entry) {
        CallableDescriptor() => entry.callers,
        StateDescriptor() => entry.readers,
        FactDescriptor() => entry.readers,
        DataStreamDescriptor() => entry.readers,
      };
      final status = access?.allows(who) == false
          ? const WordNotPermitted()
          : switch (unavailable[entry.name]) {
              final String why => WordUnavailable(why),
              _ => const WordReady(),
            };
      ((byTarget[address.target] ??= {})[name] ??= []).add(
        PublishedWord(address, portable, status),
      );
    }
    final result = <WordTarget>[];
    for (final e in byTarget.entries) {
      final names = e.value.keys.toList()..sort();
      result.add(
        WordTarget(e.key, [
          for (final name in names)
            PublishedVocabulary(
              name,
              e.value[name]!
                ..sort((a, b) => a.address.word.compareTo(b.address.word)),
            ),
        ]),
      );
    }
    result.sort((a, b) => a.principal.selector.compareTo(b.principal.selector));
    return List.unmodifiable(result);
  }

  /// The current targets, then changes in publication, access, descriptors or
  /// availability. Cancelling releases all catalog and status listeners.
  Stream<List<WordTarget>> targetChanges({String? vocabulary, String? word}) {
    _checkTargetNames(vocabulary, word);
    late StreamController<List<WordTarget>> out;
    StreamSubscription<void>? catalog, connection;
    var wasSynced = raw.synced;
    final statuses = <String, StreamSubscription<WordStatus>>{};
    List<WordTarget>? last;
    bool dirty = false, running = false, stopped = false;
    void refresh() {
      dirty = true;
      if (running || stopped) return;
      running = true;
      unawaited(() async {
        try {
          while (dirty && !stopped) {
            dirty = false;
            final next = await targets(vocabulary: vocabulary, word: word);
            if (stopped) return;
            final names = {
              for (final p in next)
                for (final v in p.vocabularies)
                  for (final w in v.words) w.address.toString(),
            };
            for (final name in statuses.keys.toList()) {
              if (!names.contains(name)) await statuses.remove(name)!.cancel();
            }
            if (stopped) return;
            for (final name in names) {
              statuses.putIfAbsent(
                name,
                () => raw
                    .statusChanges(name)
                    .listen((_) => refresh(), onError: out.addError),
              );
            }
            if (last == null ||
                !jsonEquals(
                  [for (final p in last!) p.toJson()],
                  [for (final p in next) p.toJson()],
                )) {
              last = next;
              out.add(next);
            }
          }
        } on Object catch (e, st) {
          if (!stopped) out.addError(e, st);
        } finally {
          running = false;
        }
      }());
    }

    out = StreamController(
      onListen: () {
        catalog = raw.catalogChanges.listen(
          (_) => refresh(),
          onError: out.addError,
          onDone: () {
            stopped = true;
            unawaited(out.close());
          },
        );
        connection = raw.changes({}).listen((_) {
          final synced = raw.synced;
          if (synced == wasSynced) return;
          wasSynced = synced;
          refresh();
        }, onError: out.addError);
        refresh();
      },
      onCancel: () async {
        stopped = true;
        await catalog?.cancel();
        await connection?.cancel();
        final current = statuses.values.toList();
        statuses.clear();
        await Future.wait([for (final sub in current) sub.cancel()]);
      },
    );
    return out.stream;
  }
}
