part of 'registry.dart';

/// Causal lookup and bounded, payload-free observations for host tools.
extension RegistryDiagnostics on Registry {
  /// Metadata of recent decisions, oldest first, bounded by host history limits.
  List<JournalDiagnostic> get diagnostics => List.unmodifiable(_diagnostics);

  /// Calls admitted to inspection which have not entered their handlers yet.
  List<JournalDiagnostic> get pending =>
      List.unmodifiable(_pendingCalls.values);

  /// One retained message, including active operations. No second payload cache.
  JournalEntry? message(String id, {Principal? by}) {
    JournalEntry? found;
    final completed = _recentCalls[id];
    final active = _running[id];
    if (completed?.ambiguous == true || active?.ambiguous == true) {
      return JournalDiagnostic(
        id: id,
        word: active?.command ?? completed!.command,
        cause: Cause(
          active?.cause.by ?? completed!.cause.by,
          unresolvedParent: id,
        ),
        at: active?.started ?? completed!.finished,
        event: 'id.ambiguous',
        epoch: epoch,
        n: 0,
      );
    }
    if (_recentCalls[id] case final c?) {
      found = JournalEnd(c, epoch: epoch, n: 0);
    } else if (_running[id] case final c?) {
      found = JournalStart(c, epoch: epoch, n: 0);
    } else if (_recentById[id] case final f?) {
      found = JournalFact(f, epoch: epoch, n: 0);
    } else {
      for (final tick in _retained.toList().reversed) {
        for (final c in tick.changes.reversed) {
          if (c.id == id) {
            found = JournalWrite(c, epoch: epoch, n: 0);
            break;
          }
        }
        if (found != null) break;
      }
      if (found == null) {
        for (final d in _diagnostics.toList().reversed) {
          if (d.id == id) {
            found = d;
            break;
          }
        }
      }
      found ??= _pendingCalls[id];
      if (found == null) {
        if (_activeStreams[id] case final stream?) {
          found = JournalDiagnostic(
            id: id,
            word: stream.word,
            cause: stream.cause,
            at: stream.startedAt,
            event: 'stream.opened',
            epoch: epoch,
            n: 0,
            data: {'kind': stream.kind},
          );
        }
      }
    }
    if (found == null || by == null) return found;
    final declared = _declared(found.word);
    final readable =
        declared != null &&
        switch (declared) {
          CallableDescriptor() => _accessFor(found.word, by) != Access.deny,
          _ => mayRead(by, found.word),
        };
    return readable
        ? found
        : JournalEntry.fromJson(found.toJson(payloads: false));
  }

  /// Resolves an RPC parent without trusting a peer's claimed attribution.
  Cause causeFrom(String? parent, Principal by, {bool served = false}) {
    if (parent == null) return Cause(by);
    final entry = message(parent);
    final allowed = switch (entry) {
      JournalFact() || JournalWrite() =>
        _declared(entry!.word) != null && mayRead(by, entry.word),
      JournalStart() || JournalEnd() => served,
      JournalDiagnostic(:final event) => served && event.startsWith('stream.'),
      null => false,
    };
    return allowed
        ? entry!.cause.child(parent, by: by, word: entry.word)
        : Cause(by, unresolvedParent: parent);
  }

  /// Records a boundary decision without recording arguments or results.
  void observeDecision({
    required String operation,
    required String word,
    required Principal by,
    required String event,
    Map<String, Object?> data = const {},
  }) {
    _decision(operation, word, Cause(by), event, data);
  }

  /// Inspects a call made or served by this participant, within retained history.
  Map<String, Object?> inspectCall(String id, {Principal? by}) {
    JournalEntry? entry = message(id);
    if (entry == null && by != null) {
      entry = message('${by.whole.selector}#$id');
    }
    final scoped = by == null ? id : '${by.whole.selector}#$id';
    final operation =
        entry?.id ??
        (_diagnostics.any((d) => d.data['operation'] == scoped) ? scoped : id);
    bool visible(Cause cause, String word) =>
        by == null ||
        cause.by.whole == by.whole ||
        (word.contains('/') && WordAddress.parse(word).target == by.whole);
    if (entry != null && !visible(entry.cause, entry.word)) {
      throw StateError('may not inspect call $id');
    }
    final decisions = [
      for (final d in _diagnostics)
        if (d.data['operation'] == operation && visible(d.cause, d.word)) d,
    ];
    if (entry == null && decisions.isEmpty) {
      return {'id': id, 'gap': 'operation is not retained'};
    }
    final path = _pathFrom(entry?.cause, by: by);
    return {
      'id': operation,
      'epoch': epoch,
      'running': _running.containsKey(operation),
      'pending': _pendingCalls.containsKey(operation),
      if (entry != null) 'message': entry.toJson(),
      'decisions': [for (final d in decisions) d.toJson()],
      if (path.trail.isNotEmpty)
        'trail': [for (final e in path.trail) e.toJson()],
      if (path.gap != null) 'gap': path.gap,
    };
  }

  /// Recent changes of one exact state/key, across conversations, oldest first.
  List<StateChange> history(String state, {String? key, int count = 100}) {
    state = canonical(state);
    final result = <StateChange>[];
    final max = count.clamp(0, limits.retainTicks);
    if (max == 0) return result;
    for (final tick in _retained.toList().reversed) {
      for (final change in tick.changes.reversed) {
        if (change.state == state && change.key == key) {
          result.add(change);
          if (result.length >= max) return result.reversed.toList();
        }
      }
    }
    return result.reversed.toList();
  }
}

extension on Registry {
  ({List<JournalEntry> trail, String? gap}) _pathFrom(
    Cause? cause, {
    Principal? by,
  }) {
    final trail = <JournalEntry>[];
    var parent = cause?.parent;
    String? gap = cause?.unresolvedParent == null
        ? null
        : 'unresolved parent ${cause!.unresolvedParent}';
    final seen = <String>{};
    while (parent != null) {
      if (!seen.add(parent)) {
        gap = 'cycle at $parent';
        break;
      }
      if (trail.length >= 10) {
        gap = 'depth limit at $parent';
        break;
      }
      final entry = message(parent, by: by);
      if (entry == null) {
        gap = 'parent $parent is not retained';
        break;
      }
      trail.add(entry);
      if (entry.cause.unresolvedParent case final unresolved?) {
        gap = 'unresolved parent $unresolved';
      }
      parent = entry.cause.parent;
    }
    return (trail: trail, gap: gap);
  }

  void _notice(
    String word,
    String event, {
    String? id,
    Cause? cause,
    Map<String, Object?> data = const {},
  }) {
    if (_disposing || (limits.retainTicks <= 0 && !_journal.on)) return;
    final e = JournalDiagnostic(
      id: id ?? newId(),
      word: word,
      cause: cause ?? const Cause(Principal.system),
      at: clock.now(),
      event: event,
      data: data,
      epoch: epoch,
      n: 0,
    );
    final budget = limits.retainBytes.clamp(0, 256 << 10);
    if (limits.retainTicks > 0 && budget > 0) {
      final bytes = e.retainedBytes;
      if (bytes <= budget) {
        _diagnostics.add(e);
        _diagnosticBytes += bytes;
        while (_diagnostics.length > limits.retainTicks ||
            _diagnosticBytes > budget) {
          _diagnosticBytes -= _diagnostics.removeFirst().retainedBytes;
        }
      }
    }
    _journal.diagnostic(e);
  }

  JournalDiagnostic _waiting(
    String id,
    String word,
    Cause cause,
    String event, [
    Map<String, Object?> data = const {},
  ]) {
    _decision(id, word, cause, event, data);
    return JournalDiagnostic(
      id: id,
      word: word,
      cause: cause,
      at: clock.now(),
      event: event,
      data: data,
      epoch: epoch,
      n: 0,
    );
  }

  void _decision(
    String id,
    String word,
    Cause cause,
    String event, [
    Map<String, Object?> data = const {},
  ]) => _notice(
    word,
    event,
    cause: cause.child(id, word: word),
    data: {'operation': id, ...data},
  );
}
