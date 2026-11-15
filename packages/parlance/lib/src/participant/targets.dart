part of 'participant.dart';

/// One published word, with its exact address and the caller's current status.
final class PublishedWord {
  /// A catalog entry; [descriptor] retains its portable vocabulary name.
  const PublishedWord(this.address, this.descriptor, this.status);

  /// Its exact publication address.
  final WordAddress address;

  /// Its contract, independent of the publishing instance.
  final Descriptor descriptor;

  /// Access, availability and compatibility for the requesting participant.
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

/// An instance that actually publishes words matching a discovery request.
final class WordTarget {
  /// A target and its matching, currently published words.
  WordTarget(this.principal, Iterable<PublishedWord> words)
    : words = List.unmodifiable(words);

  /// The exact whole principal; an ACL selector is never used for routing.
  final Principal principal;

  /// Actual words, each with its own access and compatibility status.
  final List<PublishedWord> words;

  /// A catalog representation for tools.
  Map<String, Object?> toJson() => {
    'principal': principal.toJson(),
    'words': [for (final w in words) w.toJson()],
  };
}

/// Discovers publications without selecting or reserving a dependency.
extension TargetDiscovery on IParticipant {
  /// Targets of [vocabulary] or [word], or all targets when unfiltered.
  /// Granted but unpublished vocabularies are not included. A supplied typed
  /// contract also checks compatibility; denied words stay visibly denied.
  Future<List<WordTarget>> targets({WordSet? vocabulary, IWord? word}) async {
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
    final byTarget = <Principal, List<PublishedWord>>{};
    final unavailable = catalog['unavailable'] as Map? ?? const {};
    for (final entry in entries.values) {
      final address = WordAddress.parse(entry.name);
      if (vocabulary != null &&
          address.word != vocabulary.name &&
          !address.word.startsWith('${vocabulary.name}.')) {
        continue;
      }
      if (word != null && address.word != word.name) {
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
      WordStatus status = access?.allows(who) == false
          ? const WordNotPermitted()
          : switch (unavailable[entry.name]) {
              final String why => WordUnavailable(why),
              _ => const WordReady(),
            };
      final expected =
          word ??
          vocabulary?.words.where((w) => w.name == address.word).firstOrNull;
      if (expected != null && status is! WordNotPermitted) {
        final breaks = wordBreaks(expected, portable);
        if (breaks.isNotEmpty) status = WordMismatch(breaks);
      }
      (byTarget[address.target] ??= []).add(
        PublishedWord(address, portable, status),
      );
    }
    final result = [
      for (final e in byTarget.entries) WordTarget(e.key, e.value),
    ];
    result.sort((a, b) => a.principal.selector.compareTo(b.principal.selector));
    return List.unmodifiable(result);
  }

  /// The current targets, then changes in publication, access, schema or
  /// availability. Cancelling releases all catalog and status listeners.
  Stream<List<WordTarget>> targetChanges({WordSet? vocabulary, IWord? word}) {
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
                for (final w in p.words) w.address.toString(),
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
