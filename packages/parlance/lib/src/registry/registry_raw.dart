part of 'registry.dart';

/// What the registry does on behalf of whoever it is told (SPEC §22):
/// defines words with no vocabulary to keep them in, calls and writes as
/// any principal, guards every command. The package's own, for what it
/// builds on the registry (participants, sessions, views, tests); not
/// exported, so a host's code reaches the registry through participants
/// only, as the one each part is.
extension RawRegistry on Registry {
  /// Runs [f] when the registry is disposed, before it closes: what holds
  /// it (its participants) goes first.
  void beforeDispose(void Function() f) => _beforeDispose.add(f);

  /// [command]'s availability may have changed without a tick (SPEC §6.5).
  void availabilityChanged(String command) {
    _availabilityMoved++;
    if (!_availability.isClosed) _availability.add(canonical(command));
  }

  /// Why [command] cannot run now (it is not there, or its owner says it
  /// is unavailable), or null when it can. Guards are not asked: they judge
  /// a call, not a command.
  String? whyUnavailable(String command) {
    final c = _commands[canonical(command)];
    if (c == null) return 'no command $command';
    return c.available?.call();
  }

  /// Whether [by] can use the word [name] now (SPEC §6.5): missing from
  /// the catalog, not permitted to it, a command unavailable now, or
  /// ready. An old name stands for its word.
  WordStatus statusOf(String name, {required Principal by}) {
    final n = canonical(name);
    if (_commands[n] case final c?) {
      if (!c.descriptor.callers.allows(by)) return const WordNotPermitted();
      if (c.available?.call() case final why?) return WordUnavailable(why);
      return const WordReady();
    }
    if (!_states.containsKey(n) && !_facts.containsKey(n)) {
      return const WordMissing();
    }
    return mayRead(by, n) ? const WordReady() : const WordNotPermitted();
  }

  /// [statusOf] now, then whenever it changes: a word comes or goes, an
  /// old name moves, or a tick changes what a command's availability check
  /// reads.
  Stream<WordStatus> statusChanges(String name, {required Principal by}) {
    late StreamController<WordStatus> out;
    StreamSubscription<CatalogChange>? catalog;
    StreamSubscription<Tick>? ticks;
    StreamSubscription<String>? availability;
    WordStatus? last;
    void tell() {
      final now = statusOf(name, by: by);
      if (now == last) return;
      last = now;
      out.add(now);
    }

    out = StreamController<WordStatus>(
      onListen: () {
        tell();
        // It ends with the registry.
        catalog = catalogChanges.listen((_) => tell(), onDone: out.close);
        ticks = this.ticks.listen((_) => tell());
        availability = availabilityChanges.listen((_) => tell());
      },
      onCancel: () async {
        await catalog?.cancel();
        await ticks?.cancel();
        await availability?.cancel();
      },
    );
    return out.stream;
  }

  /// Whether [by] may read state [name]'s values, or hear fact [name], over
  /// remote and MCP (its `readers`); true for a word there is
  /// not.
  bool mayRead(Principal by, String name) =>
      (_states[canonical(name)]?.descriptor.readers ??
              _facts[canonical(name)]?.descriptor.readers)
          ?.allows(by) ??
      true;

  /// The catalog as [by] sees it: [describe], with what [by] may call
  /// (`access`: command to allow, warn or deny), the commands that cannot
  /// run now, and why (`unavailable`), and the states whose values it may
  /// not read and the facts it may not hear (`unreadable`).
  Map<String, Object?> describeFor(Principal by) => {
    ...describe(),
    if (_unreadable(by) case final u when u.isNotEmpty) 'unreadable': u,
    'access': {
      for (final c in _commands.values)
        c.descriptor.name: c.descriptor.callers.accessOf(by).name,
    },
    'unavailable': unavailable,
  };

  /// The commands that cannot run now, and why their owners say so.
  Map<String, String> get unavailable => {
    for (final name in _commands.keys) name: ?whyUnavailable(name),
  };

  /// [unavailable] as it is after the last tick: what every session's
  /// feed tells after a tick, the checks asked once for all of them until
  /// the next tick, a catalog change or an owner's word moves them.
  Map<String, String> get unavailableAfterTick {
    if (_unavailableNow case (
      :final seq,
      :final moved,
      :final why,
    ) when seq == this.seq && moved == _availabilityMoved) {
      return why;
    }
    final why = Map<String, String>.unmodifiable(unavailable);
    _unavailableNow = (seq: seq, moved: _availabilityMoved, why: why);
    return why;
  }

  /// Registers an entity kind (SPEC §3); withdraw it with the handle.
  IHandle registerKind(EntityKind kind) {
    if (_kinds.containsKey(kind.name)) {
      throw StateError('kind ${kind.name} exists');
    }
    _kinds[kind.name] = kind;
    _announce(KindChanged(kind.name));
    return Disposer(() {
      if (_kinds[kind.name] == kind) {
        _kinds.remove(kind.name);
        _announce(KindChanged(kind.name));
      }
    });
  }

  /// The entities of [kind] changed.
  void entitiesChanged(String kind) => _announce(KindChanged(kind));

  /// Defines a state; the returned writer is its only write handle.
  ///
  /// Given a [shape] that keeps its values as they are, the registry keeps
  /// them so (SPEC §18) and the writer takes Dart values; else it keeps
  /// JSON, and the writer takes JSON.
  RawStateWriter defineState(
    StateDescriptor d, {
    required Principal by,
    Shape<Object?>? shape,
  }) {
    _checkFree(d.name);
    _checkKnown(d);
    final kept = shape != null && shape.keptAsIs ? shape : null;
    final keep = kept ?? JsonValue(d.type);
    final local = LocalKeyedState<String?, Object?>(
      hub: _hub,
      equals: keep.equals,
    );
    _names[local] = d.name;
    _shapeOf[local] = keep;
    _states[d.name] = _StateEntry(d, local, keep);
    _announce(DescriptorAdded(d));
    return RawStateWriter._(this, d, by, kept);
  }

  /// Defines a command served by [handler]; dispose the handle to remove it.
  IHandle defineCommand(
    CommandDescriptor d,
    CommandHandler handler, {
    Availability? available,
    Shape<Object?>? params,
    Shape<Object?>? returns,
  }) {
    _checkFree(d.name);
    _checkKnown(d);
    final local = LocalCommand<CommandCall, Object?>();
    _commands[d.name] = _CommandEntry(
      d,
      local,
      local.serve(handler),
      available,
      params: params,
      returns: returns,
    );
    _announce(DescriptorAdded(d));
    return Disposer(() => _undefine(d.name));
  }

  /// Defines a query answered by [handler] (SPEC §6.6); dispose the handle
  /// to remove it.
  IHandle defineQuery(
    QueryDescriptor d,
    CommandHandler handler, {
    Availability? available,
    Shape<Object?>? params,
    Shape<Object?>? returns,
  }) {
    _checkFree(d.name);
    _checkKnown(d);
    final local = LocalCommand<CommandCall, Object?>();
    _commands[d.name] = _CommandEntry(
      d,
      local,
      local.serve(handler),
      available,
      params: params,
      returns: returns,
    );
    _announce(DescriptorAdded(d));
    return Disposer(() => _undefine(d.name));
  }

  /// Defines a fact; the returned emitter belongs to the definer.
  ///
  /// Given a [shape] that keeps its payloads as they are, the registry
  /// keeps them so (SPEC §18) and the emitter takes Dart values; else
  /// JSON.
  RawFactEmitter defineFact(
    FactDescriptor d, {
    required Principal by,
    Shape<Object?>? shape,
  }) {
    _checkFree(d.name);
    _checkKnown(d);
    final kept = shape != null && shape.keptAsIs ? shape : null;
    final keep = kept ?? JsonValue(d.type);
    final local = LocalFact<Object?>(hub: _hub);
    _facts[d.name] = _FactEntry(d, local, keep);
    _names[local] = d.name;
    _shapeOf[local] = keep;
    _announce(DescriptorAdded(d));
    return RawFactEmitter._(
      this,
      d,
      by,
      local.claim(),
      definer: true,
      shape: kept,
    );
  }

  /// Runs [body] synchronously and commits everything it wrote as one tick
  /// (SPEC §7). Batches nest; the outermost commits.
  void batch(void Function() body) {
    try {
      _hub.batch(body);
    } finally {
      if (!_hub.writing && _retired.isNotEmpty) {
        for (final local in [..._retired]) {
          _retire(local);
        }
        _retired.clear();
      }
    }
  }

  /// The word named [name] (or an old name of it) as it is defined now;
  /// null when there is none.
  Descriptor? descriptorOf(String name) {
    final n = canonical(name);
    return _states[n]?.descriptor ??
        _commands[n]?.descriptor ??
        _facts[n]?.descriptor;
  }

  /// The value of [state] (of [key]); inside a batch, the batch's own
  /// writes count (SPEC §7). Null when there is none.
  Object? read(String state, {String? key}) {
    final e = _states[canonical(state)];
    return e?.jsonOf(key, e.local.read(key));
  }

  /// [read] as [shape] has it (SPEC §18): the value itself when the
  /// registry keeps it by [shape], else its JSON decoded.
  T? readAs<T>(String state, Shape<T> shape, {String? key}) {
    final e = _states[canonical(state)];
    if (e == null) return null;
    final v = e.local.read(key);
    if (v == null) return null;
    return identical(e.shape, shape)
        ? v as T
        : decodeKnown(shape, e.jsonOf(key, v));
  }

  /// Whether [state] (of [key]) has a committed value.
  bool has(String state, {String? key}) =>
      _states[canonical(state)]?.local.has(key) ?? false;

  /// Every committed value of [state], by key (null for an unkeyed one).
  Map<String?, Object?> readAll(String state) {
    final e = _states[canonical(state)];
    if (e == null) return const {};
    if (e.shape is JsonValue) return e.local.values;
    return {
      for (final MapEntry(:key, :value) in e.local.values.entries)
        key: e.jsonOf(key, value),
    };
  }

  /// The value of [state] (of [key]) now, then on every change; null when
  /// there is none.
  Stream<Object?> watch(String state, {String? key}) =>
      _watch(state, key, () => read(state, key: key), (c) => c.value);

  /// [watch] as [shape] has it (SPEC §18).
  Stream<T?> watchAs<T>(String state, Shape<T> shape, {String? key}) =>
      _watch<T>(
        state,
        key,
        () => readAs(state, shape, key: key),
        (c) => c.removed ? null : _valueAs(c, shape),
      );

  static const Object _other = Object();

  T? _valueAs<T>(StateChange c, Shape<T> shape) {
    final kept = keptValueOf(c, shape, _other);
    return identical(kept, _other) ? decodeKnown(shape, c.value) : kept as T?;
  }

  T _payloadAs<T>(FactMessage m, Shape<T> shape) {
    final kept = keptPayloadOf(m, shape, _other);
    return (identical(kept, _other) ? decodeWith(shape, m.payload) : kept) as T;
  }

  Stream<V?> _watch<V>(
    String state,
    String? key,
    V? Function() now,
    V? Function(StateChange c) of,
  ) {
    final at = (state, key);
    late StreamController<V?> out;
    out = StreamController<V?>(
      onListen: () {
        out.add(now());
        _tell[out] = of;
        _readNow[out] = now;
        // Ticks committed before it read are on their way to the others'
        // listener still: what it read is newer than they are.
        (_watchers[at] ??= {})[out] = seq;
        _watching ??= ticks.listen(_toWatchers, onDone: _endWatchers);
      },
      onCancel: () {
        _tell.remove(out);
        _readNow.remove(out);
        final set = _watchers[at];
        if (set == null) return;
        set.remove(out);
        if (set.isEmpty) _watchers.remove(at);
        if (_watchers.isEmpty) {
          _watching?.cancel();
          _watching = null;
        }
      },
    );
    return out.stream;
  }

  /// [facts] as [shape] has them (SPEC §18); one whose payload [shape]
  /// cannot read is not heard (SPEC §25.2).
  Stream<(T, FactMessage)> factsAs<T>(String fact, Shape<T> shape) =>
      facts(fact: fact).expand((m) {
        try {
          return [(_payloadAs(m, shape), m)];
        } on Object {
          return const [];
        }
      });

  /// Facts as they are committed, of [fact] only when given.
  Stream<FactMessage> facts({String? fact}) {
    if (fact == null) return ticks.expand((t) => t.facts);
    // What [fact] stands for at each tick: an old name hears the word it
    // stands for now, renamed while it listens (SPEC §6.4).
    return ticks.expand((t) {
      final name = canonical(fact);
      return t.facts.where((f) => f.fact == name);
    });
  }

  /// The last [n] facts of [fact], oldest first.
  List<FactMessage> recent(String fact, [int? n]) {
    final q = _recent[canonical(fact)];
    if (q == null || (n != null && n <= 0)) return const [];
    final all = q.toList();
    return n == null || n >= all.length ? all : all.sublist(all.length - n);
  }

  /// The fact of id [id] among those kept, or null: what follows from it
  /// (a remote participant's answer to it) takes its cause.
  FactMessage? recentFact(String id) => _recentById[id];

  /// The feed (SPEC §12): resumes after `since` of [epoch] when it is still
  /// retained, else starts with a snapshot.
  Stream<FeedItem> feed({String? epoch, int? since}) {
    late StreamController<FeedItem> out;
    StreamSubscription<Tick>? sub;
    out = StreamController<FeedItem>(
      onListen: () {
        var last = seq;
        final canResume =
            epoch == this.epoch &&
            since != null &&
            since <= seq &&
            (since == seq ||
                (_retained.isNotEmpty && _retained.first.from <= since + 1));
        if (canResume) {
          for (final t in _retained) {
            if (t.to > since) out.add(t);
          }
        } else {
          out.add(
            Snapshot(
              epoch: this.epoch,
              seq: seq,
              states: {for (final e in _states.keys) e: readAll(e)},
              factsLost: since != null,
            ),
          );
        }
        sub = ticks.listen((t) {
          if (t.to <= last) return;
          last = t.to;
          out.add(t);
        }, onDone: out.close);
      },
      onCancel: () => sub?.cancel(),
    );
    return out.stream;
  }

  /// [by] read [word] once, from outside the build: a session's read of a
  /// fact's recent ones or a state's why, an agent's read (SPEC §6.8).
  /// Calls and asks are counted by the registry itself.
  void usedBy(String word, Principal by) => _uses.read(word, by);

  /// [by]'s code was built against [schemas], each word's schema entry by
  /// name (SPEC §6.9): judged now, and whenever one is defined again,
  /// until the handle is disposed. A word told again is held to the
  /// newest; one past [builtPerPrincipal] is not kept.
  IHandle builtAgainst(
    Principal by,
    Map<String, Object?> schemas, {
    String? from,
  }) => _builtAgainst.tell(by, schemas, from: from);

  /// The schema told it under [print], a fingerprint (SPEC §25.4); null
  /// when it knows none.
  Object? knownSchema(String print) => _builtAgainst.knownSchema(print);

  /// [by] listens to [word] until the handle is disposed: a session's
  /// subscription (SPEC §6.8). Null while there is no word of that name:
  /// ask again when one comes (`catalogChanges`).
  IHandle? listenedBy(String word, Principal by) => _uses.listening(word, by);

  /// Calls [command] on behalf of [by] (SPEC §9). A repeated [id] within
  /// the dedup window answers the first call's result without running it
  /// again. A call made by a handler passes [cause]; without it,
  /// the call starts a new chain.
  Future<CallResult<Object?>> call(
    String command,
    Map<String, Object?> params, {
    required Principal by,
    String? id,
    Cause? cause,
  }) => callKept(command, Kept.json(params), by: by, id: id, cause: cause);

  /// [call] with [params] as their shape has them (SPEC §18): a command
  /// that keeps its params by that shape takes them as they are.
  Future<CallResult<Object?>> callKept(
    String command,
    Kept params, {
    required Principal by,
    String? id,
    Cause? cause,
  }) {
    final asked = command;
    command = canonical(command);
    if (_commands.containsKey(command)) _uses.called(asked, by);
    final callId = id ?? newId();
    cause = _inConversation(cause ?? Cause(by));
    _converse(callId, command, cause);
    final query = _commands[command]?.query ?? false;
    // A query may ask another; a command it may not call.
    if (!query) refuseInQuery('call $command');
    if (query) {
      // A query only answers: nothing to hold an id to, nothing to record.
      return _run(callId, command, params, cause, record: false);
    }
    final now = clock.now();
    _forget(_calls, (c) => c.at, now);
    if (_calls[callId] case final seen?) {
      // An id stands for one call: another one with it is refused, not
      // answered the first call's result.
      if (seen.command != command ||
          seen.by != by ||
          !jsonEquals(seen.params.json, params.json)) {
        return Future.value(
          CallRefused(
            Refusal.idConflict,
            'id $callId was given to another call',
          ),
        );
      }
      return seen.result;
    }
    final result = _run(callId, command, params, cause);
    // Only an id the caller gave can be given again: one made here is
    // nobody's to retry with.
    if (id != null) {
      _calls[callId] = _Seen(
        now,
        command,
        params.shape == null ? Kept.json(freezeJson(params.json)) : params,
        by,
        result,
      );
      if (_calls.length > dedupLimit) _calls.remove(_calls.keys.first);
    }
    return result;
  }

  /// Adds a guard (SPEC §10), asked for every call in the order guards
  /// were added.
  IHandle addGuard(String id, GuardCheck check) {
    if (_guards.containsKey(id)) throw StateError('guard $id exists');
    final g = _Guard(id, check);
    _guards[id] = g;
    return Disposer(() {
      if (_guards[id] == g) _guards.remove(id);
    });
  }

  /// Adds a guard whose check another makes across a connection (SPEC
  /// §22.4): asked in its turn with the guards; no answer within [timeout]
  /// denies.
  IHandle addAskedGuard(
    String id,
    Future<String?> Function(PendingCall call) ask, {
    Duration timeout = const Duration(seconds: 2),
    bool Function(String command)? judges,
  }) {
    if (_guards.containsKey(id)) throw StateError('guard $id exists');
    final g = _Guard.asked(id, ask, timeout, judges);
    _guards[id] = g;
    return Disposer(() {
      if (_guards[id] == g) _guards.remove(id);
    });
  }
}
