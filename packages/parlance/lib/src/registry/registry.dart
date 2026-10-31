import 'dart:async';
import 'dart:collection';

import 'package:clock/clock.dart' as clock_zone;
import 'package:clock/clock.dart' show Clock;
import 'package:rpc_dart/logger.dart';

import '../core/core.dart';

export 'package:rpc_dart/logger.dart'
    show LogScope, LogSpanHandle, LogSpanStatus, RpcLogLevel;
export '../core/core.dart' show Disposer, IHandle;

import 'built_against.dart';
import 'cause.dart';
import 'descriptors.dart';
import 'ids.dart';
import 'journaling.dart';
import 'json.dart';
import 'messages.dart';
import 'shapes.dart';
import 'tracing.dart';
import 'types.dart';
import 'uses.dart';
import 'cancellation.dart';

export 'cancellation.dart' show CancellationToken;

part 'registry_calls.dart';
part 'registry_words.dart';
part 'registry_raw.dart';

/// How much a host keeps of what passed (SPEC §14): what it still answers
/// a retry, a feed catching up and `recent` from. The defaults suit an
/// app; a phone may keep less.
final class HostLimits {
  const HostLimits({
    this.dedupWindow = const Duration(minutes: 10),
    this.dedupLimit = 10000,
    this.retainTicks = 1000,
    this.retainBytes = 4 << 20,
    this.recentPerFact = 100,
    this.usersPerWord = 64,
  });

  /// A host that keeps nothing past what is now: no trail for `explain`,
  /// no `recent` facts, and a feed that fell behind takes a snapshot. What
  /// it does is the same; a retry of a call still gets its first answer.
  static const light = HostLimits(
    retainTicks: 0,
    retainBytes: 0,
    recentPerFact: 0,
  );

  /// How long ids of calls and facts are remembered to drop repeats: a
  /// retry of the same id gets the first answer.
  final Duration dedupWindow;

  /// How many ids of calls, and of facts, are remembered at most within
  /// [dedupWindow]: past it the oldest go, so a burst of calls (a fader
  /// dragged) does not hold ten minutes of them. A retry of one forgotten
  /// runs again.
  final int dedupLimit;

  /// How many ticks a feed can resume from.
  final int retainTicks;

  /// About how many bytes of values each history keeps: the retained ticks,
  /// the call records, the recent facts of each name. Whichever bound comes
  /// first, this or the count, drops the oldest, and the newest is always
  /// kept, however big; a feed behind what is kept resumes from a snapshot.
  /// Values are weighed as their JSON, roughly.
  final int retainBytes;

  /// How many of each fact are kept for `recent`.
  final int recentPerFact;

  /// How many principals the uses of one word tell apart (SPEC §6.8);
  /// past them a use is counted under the principal's kind alone
  /// (`guest`), so many guests do not grow it, and no use goes unseen.
  final int usersPerWord;
}

/// What a caller's cancel answers in place of a handler's answer: no
/// answer can be it.
final Object _cancelledMark = Object();

/// The registry: the vocabulary, its values, calls, guards and the feed (SPEC §§5–12).
///
/// One isolate, one writer: every commit happens here in order, so seq is a
/// total order. Participants hold handles and never each other.
final class Registry implements ITypeContext {
  Registry({
    this.limits = const HostLimits(),
    Clock? clock,
    ErrorSink? onError,
    LogScope? log,
  }) : clock = clock ?? clock_zone.clock,
       log = log ?? LogScope.noop,
       _traced = log != null && !identical(log, LogScope.noop),
       _callLog = (log ?? LogScope.noop).child('calls'),
       _tickLog = (log ?? LogScope.noop).child('ticks'),
       _catalogLog = (log ?? LogScope.noop).child('catalog'),
       _onError = _logged(log, onError ?? Zone.current.handleUncaughtError),
       epoch = newId() {
    _hub = LocalHub(onCommit: _committed);
  }

  /// Commits every state value and fact of the registry (SPEC §7, §21).
  late final LocalHub _hub;

  /// How much it keeps of what passed ([HostLimits]).
  final HostLimits limits;

  /// This registry's run; seq counts within it.
  final String epoch;

  /// Where the registry and its clients read the time; the zone's clock
  /// when the registry was made, unless given.
  final Clock clock;

  final ErrorSink _onError;

  /// Where the registry logs (SPEC §9.2): a span for every call its
  /// handler serves, whatever the level, and refusals, ticks, the
  /// catalog's changes and errors, by level. `LogScope.noop` unless given:
  /// then nothing is logged, and nothing of it is made. Its parts log as
  /// its children: `calls`, `ticks`, `catalog`.
  final LogScope log;
  final LogScope _callLog;
  final LogScope _tickLog;
  final LogScope _catalogLog;

  /// Whether it has a log to keep spans and traces for.
  final bool _traced;

  static ErrorSink _logged(LogScope? log, ErrorSink sink) =>
      log == null || identical(log, LogScope.noop)
      ? sink
      : (e, s) {
          log.error('error', error: e, stackTrace: s);
          sink(e, s);
        };

  /// The seq of the last commit.
  int get seq => _hub.seq;

  // --- Catalog ---------------------------------------------------------------

  final Map<String, Choices> _choices = {};
  final Map<String, _StateEntry> _states = {};
  final Map<String, _CommandEntry> _commands = {};
  final Map<String, _FactEntry> _facts = {};

  /// The word each local state and fact holds.
  final Map<Object, String> _names = Map.identity();

  /// The shape each local state and fact keeps its values by.
  final Map<Object, Shape<Object?>> _shapeOf = Map.identity();
  final StreamController<CatalogChange> _catalog = StreamController.broadcast();

  void _announce(CatalogChange c) {
    _availabilityMoved++;
    switch (c) {
      case DescriptorAdded(:final descriptor):
        if (_catalogLog.isEnabled(RpcLogLevel.info)) {
          _catalogLog.info('defined', data: {'word': descriptor.name});
        }
        _builtAgainst.wordChanged(descriptor.name);
      case DescriptorRemoved(:final descriptor):
        if (_catalogLog.isEnabled(RpcLogLevel.info)) {
          _catalogLog.info('removed', data: {'word': descriptor.name});
        }
        _builtAgainst.wordChanged(descriptor.name);
      case AliasChanged(:final alias):
        if (_catalogLog.isEnabled(RpcLogLevel.info)) {
          _catalogLog.info('alias changed', data: {'alias': alias});
        }
        _builtAgainst.aliasChanged(alias);
        _aliasWatchers(alias);
      case ChoicesChanged(:final name):
        if (_catalogLog.isDebug) {
          _catalogLog.debug('choices changed', data: {'name': name});
        }
    }
    if (!_catalog.isClosed) _catalog.add(c);
  }

  /// Additions, removals and changes of choices, in order.
  Stream<CatalogChange> get catalogChanges => _catalog.stream;

  final StreamController<String> _availability = StreamController.broadcast();

  /// Bumped whenever what the commands' checks answer may change but for
  /// a tick: the catalog changed, or an owner said a check would answer
  /// otherwise.
  int _availabilityMoved = 0;

  /// What `unavailable` answered, at which seq and move: every feed asks
  /// it after every tick, and the checks are asked once for all of them.
  ({int seq, int moved, Map<String, String> why})? _unavailableNow;

  /// Commands whose whyNot would answer otherwise now, though
  /// no tick says so: an owner across a connection told it, or one whose
  /// check reads what the registry does not keep.
  Stream<String> get whyNotChanges => _availability.stream;

  /// Every descriptor there is now.
  List<Descriptor> get catalog => [
    for (final s in _states.values) s.descriptor,
    for (final c in _commands.values) c.descriptor,
    for (final f in _facts.values) f.descriptor,
  ];

  Iterable<Choices> get choices => _choices.values;

  StateDescriptor? stateDescriptor(String name) =>
      _states[canonical(name)]?.descriptor;

  CommandDescriptor? commandDescriptor(String name) =>
      switch (_commands[canonical(name)]?.descriptor) {
        final CommandDescriptor d => d,
        _ => null,
      };

  QueryDescriptor? queryDescriptor(String name) =>
      switch (_commands[canonical(name)]?.descriptor) {
        final QueryDescriptor d => d,
        _ => null,
      };

  /// A command's or a query's descriptor: what is called by [name].
  CallableDescriptor? callableDescriptor(String name) =>
      _commands[canonical(name)]?.descriptor;

  FactDescriptor? factDescriptor(String name) =>
      _facts[canonical(name)]?.descriptor;

  /// The catalog as JSON (SPEC §14): its epoch and seq, how long a call id
  /// answers its first result, the descriptors and the choices (`kinds`).
  Map<String, Object?> describe() => {
    'epoch': epoch,
    'seq': seq,
    'dedupWindowMs': limits.dedupWindow.inMilliseconds,
    'descriptors': [for (final d in catalog) d.toJson()],
    'kinds': [for (final k in _choices.values) k.toJson()],
    if (_aliases.isNotEmpty) 'aliases': Map.of(_aliases),
  };

  List<String> _unreadable(Principal by) => [
    for (final s in _states.values)
      if (!(s.descriptor.readers?.allows(by) ?? true)) s.descriptor.name,
    for (final f in _facts.values)
      if (!(f.descriptor.readers?.allows(by) ?? true)) f.descriptor.name,
  ];

  @override
  bool hasChoices(String name) => _choices.containsKey(name);

  @override
  bool hasChoice(String name, String id) =>
      _choices[name]?.contains(id) ?? false;

  void _checkFree(String name) {
    if (_states.containsKey(name) ||
        _commands.containsKey(name) ||
        _facts.containsKey(name)) {
      throw StateError('$name is defined');
    }
    if (_aliases[name] case final now?) {
      throw StateError('$name is an old name of $now');
    }
  }

  /// A word of a type this parlance does not know is not taken (SPEC
  /// §14): what its values may be, the registry could not check.
  void _checkKnown(Descriptor d) {
    final types = switch (d) {
      StateDescriptor(:final type) || FactDescriptor(:final type) => [type],
      CallableDescriptor(:final params, :final returns) => [params, returns],
    };
    for (final t in types) {
      if (unknownTypeIn(t) case final u?) {
        throw ArgumentError(
          '${d.name}: ${u.json['type']} is no type this parlance knows',
        );
      }
    }
  }

  final Map<String, String> _aliases = {};

  /// The old names of words, each with the name it stands for now.
  Map<String, String> get aliases => Map.unmodifiable(_aliases);

  /// The name [name] stands for: the word it was renamed to, or itself.
  String canonical(String name) => _aliases[name] ?? name;

  /// The local states of words that went inside a batch: their removals commit
  /// with it, then they go.
  final Set<LocalKeyedState<String?, Object?>> _retired = Set.identity();

  void _retire(LocalKeyedState<String?, Object?> local) {
    local.close();
    _names.remove(local);
    _shapeOf.remove(local);
  }

  void _undefine(String name) {
    if (_states[name] case final s?) {
      // The values go in one tick, as removals everyone who follows them
      // is told; what was written of them in the batch running now goes
      // with them, uncommitted.
      batch(() => s.writer.clear(tag: Cause(Principal.system)));
      _states.remove(name);
      s.writer.dispose();
      // Inside an outer batch the removals wait for it: the local state stays for
      // them to commit against, and goes after.
      if (_hub.writing) {
        _retired.add(s.local);
      } else {
        _retire(s.local);
      }
      _announce(DescriptorRemoved(s.descriptor));
    } else if (_commands.remove(name) case final c?) {
      c.serving.dispose();
      _announce(DescriptorRemoved(c.descriptor));
    } else if (_facts.remove(name) case final f?) {
      f.local.close();
      _names.remove(f.local);
      _shapeOf.remove(f.local);
      _announce(DescriptorRemoved(f.descriptor));
    } else {
      return;
    }
    _uses.forget(name);
  }

  // --- Ticks -----------------------------------------------------------------

  final StreamController<Tick> _ticks = StreamController.broadcast();

  /// The weight of each value held now, by its state and key: what the
  /// change that replaces it weighed when it came.
  final Map<(Object, Object?), int> _heldWeights = {};

  final ListQueue<Tick> _retained = ListQueue();
  final ListQueue<int> _retainedWeights = ListQueue();
  int _retainedBytes = 0;
  final Map<String, _RecentFacts> _recent = {};

  /// The facts [_recent] keeps, by id: what a message follows from is
  /// found at once, however many facts are kept.
  final Map<String, FactMessage> _recentById = {};

  /// Every commit, in seq order, delivered asynchronously.
  Stream<Tick> get ticks => _ticks.stream;

  void _writeState(
    StateDescriptor d,
    String? key,
    Object? value,
    Cause cause, {
    bool asIs = false,
  }) {
    cause = _inConversation(cause);
    refuseInQuery('write ${d.name}');
    final e = _liveState(d);
    _checkKey(d, key);
    // What is the same of the value kept now passes as it is (SPEC §18).
    final was = e.local.read(key);
    final v = asIs
        ? e.shape.check(value, this, was: was)
        : _admit(e.shape, value, was);
    e.writer.set(key, v, tag: cause);
  }

  /// [json] as [shape] keeps it: checked as JSON first, so what is refused
  /// says so as the JSON's type says it, then made the Dart value [shape]
  /// keeps.
  Object? _admit(Shape<Object?> shape, Object? json, [Object? was]) =>
      shape is JsonValue
      ? shape.check(json, this, was: was)
      : shape.check(shape.fromJson(shape.type.check(json, this)), this);

  /// [params] as [shape] keeps a call's params: as they are when they
  /// come by that shape, else from their JSON.
  Kept _admitParams(Shape<Object?> shape, Kept params) {
    final v = params.shape != null && identical(params.shape, shape)
        ? shape.check(params.value, this)
        : _admit(shape, params.json);
    return Kept(v, shape is JsonValue ? null : shape);
  }

  void _removeState(StateDescriptor d, String? key, Cause cause) {
    cause = _inConversation(cause);
    refuseInQuery('remove ${d.name}');
    final e = _liveState(d);
    _checkKey(d, key);
    e.writer.remove(key, tag: cause);
  }

  _StateEntry _liveState(StateDescriptor d) {
    final e = _states[d.name];
    if (e == null || e.descriptor != d) throw StateError('${d.name} is gone');
    return e;
  }

  void _checkKey(StateDescriptor d, String? key) {
    if (d.keyed && (key == null || key.isEmpty)) {
      throw ArgumentError('${d.name} is keyed by ${d.key}: give a key');
    }
    if (!d.keyed && key != null) {
      throw ArgumentError('${d.name} has no keys');
    }
  }

  /// Logs [t]: in brief at debug, and each write and fact made in reply to
  /// a call as an event of the call's span.
  void _logTick(Tick t) {
    _trace.said(t);
    String what(StateChange c) =>
        c.key == null ? c.state : '${c.state}[${c.key}]';
    if (_tickLog.isDebug) {
      _tickLog.debug(
        'tick',
        data: {
          'seq': t.to,
          'changes': [for (final c in t.changes) what(c)],
          'facts': [for (final f in t.facts) f.fact],
        },
      );
    }
    _trace.events(t);
  }

  /// Turns what the hub committed into the registry's tick: names, ids,
  /// causes and the time.
  void _committed(LocalTick t) {
    final now = clock.now();
    final changes = <StateChange>[
      for (final c in t.changes)
        // Of a state that went, only its removals: a batch that threw puts
        // back what was written before it went.
        if (c.removed || !_retired.contains(c.state))
          keptChange(
            seq: c.seq,
            id: newId(),
            state: _names[c.state]!,
            key: c.key as String?,
            value: c.value,
            previous: c.previous,
            removed: c.removed,
            cause: c.tag! as Cause,
            at: now,
            shape: _shapeOf[c.state]!,
          ),
    ];
    final committed = <FactMessage>[
      for (final e in t.facts)
        if (e.tag case (final String id, final Cause cause))
          keptFact(
            seq: e.seq,
            id: id,
            fact: _names[e.fact]!,
            payload: e.value,
            cause: cause,
            at: now,
            shape: _shapeOf[e.fact]!,
          ),
    ];
    final tick = Tick(
      epoch: epoch,
      from: t.from,
      to: t.to,
      changes: List.unmodifiable(changes),
      facts: List.unmodifiable(committed),
    );
    _logTick(tick);
    _journal.tick(tick);
    _builtAgainst.ticked(tick);
    int weigh(Object of, Object? v) => v == null ? 8 : _shapeOf[of]!.weigh(v);
    var weight = 0;
    final factWeights = <int>[];
    for (final c in t.changes) {
      // The JSON told of a value that changed is of the value before.
      final state = _states[_names[c.state]];
      if (state != null && identical(state.local, c.state)) {
        state._json.remove(c.key);
      }
      // The value before was weighed when it came: not again.
      final at = (c.state, c.key);
      final before = _heldWeights.remove(at) ?? weigh(c.state, c.previous);
      final now = weigh(c.state, c.value);
      if (!c.removed) _heldWeights[at] = now;
      weight += now + before;
    }
    for (final e in t.facts) {
      if (e.tag is! (String, Cause)) continue;
      final w = weigh(e.fact, e.value);
      factWeights.add(w);
      weight += w;
    }
    _retained.add(tick);
    _retainedWeights.add(weight);
    _retainedBytes += weight;
    while (_retained.length > limits.retainTicks ||
        (_retained.length > 1 && _retainedBytes > limits.retainBytes)) {
      final dropped = _retained.removeFirst();
      _retainedBytes -= _retainedWeights.removeFirst();
      for (final c in dropped.changes) {
        _forgottenChanges.add((state: c.state, key: c.key));
      }
    }
    for (final (i, f) in committed.indexed) {
      final q = _recent.putIfAbsent(f.fact, _RecentFacts.new);
      q.add(f, factWeights[i]);
      _recentById[f.id] = f;
      while (q.length > limits.recentPerFact ||
          (q.length > 1 && q.bytes > limits.retainBytes)) {
        final gone = q.removeFirst();
        // An id said again past the dedup window may name a newer one.
        if (identical(_recentById[gone.id], gone)) _recentById.remove(gone.id);
      }
    }
    if (!_ticks.isClosed) _ticks.add(tick);
  }

  // --- Reading ---------------------------------------------------------------

  /// Who watches which state (of which key), each with the seq it read
  /// at: a change reaches only its own watchers, however many watch other
  /// states, and only those that read before it. By the name each gave:
  /// an old name follows the word it stands for now (SPEC §6.4), as the
  /// word is renamed while it watches.
  final Map<(String, String?), Map<StreamController<Object?>, int>> _watchers =
      {};
  StreamSubscription<Tick>? _watching;

  /// What each watcher is told of a change it follows: its JSON, or the
  /// value as the watcher's shape has it.
  final Map<StreamController<Object?>, Object? Function(StateChange)> _tell =
      Map.identity();

  /// What each watcher reads now: told when the name it gave comes to
  /// stand for another word.
  final Map<StreamController<Object?>, Object? Function()> _readNow =
      Map.identity();

  /// The registry was disposed: every watch ends.
  void _endWatchers() {
    for (final set in [..._watchers.values]) {
      for (final out in [...set.keys]) {
        unawaited(out.close());
      }
    }
    _watchers.clear();
    _tell.clear();
    _readNow.clear();
    _watching = null;
  }

  void _toWatchers(Tick t) {
    // The old names of each word, for watchers that gave one.
    final olds = <String, List<String>>{};
    for (final MapEntry(key: old, value: word) in _aliases.entries) {
      (olds[word] ??= []).add(old);
    }
    for (final c in t.changes) {
      for (final name in [c.state, ...?olds[c.state]]) {
        final set = _watchers[(name, c.key)];
        if (set == null) continue;
        for (final e in [...set.entries]) {
          if (c.seq > e.value) e.key.add(_tell[e.key]!(c));
        }
      }
    }
  }

  /// [alias] stands for another word, or none: its watchers read what it
  /// stands for now.
  void _aliasWatchers(String alias) {
    for (final MapEntry(key: (name, _), value: set) in _watchers.entries) {
      if (name != alias) continue;
      for (final out in [...set.keys]) {
        set[out] = seq;
        out.add(_readNow[out]!());
      }
    }
  }

  // --- Facts -----------------------------------------------------------------

  final LinkedHashMap<String, DateTime> _seenFacts = LinkedHashMap();

  bool _say(
    FactDescriptor d,
    LocalFactSayer<Object?> sayer,
    Object? payload,
    String id,
    Cause cause, {
    bool asIs = false,
  }) {
    final entry = _facts[d.name];
    if (entry?.descriptor != d) throw StateError('${d.name} is gone');
    refuseInQuery('say ${d.name}');
    final now = clock.now();
    _forget(_seenFacts, (at) => at, now);
    if (_seenFacts.containsKey(id)) return false;
    final v = asIs
        ? entry!.shape.check(payload, this)
        : _admit(entry!.shape, payload);
    cause = _inConversation(cause);
    _converse(id, d.name, cause);
    _seenFacts[id] = now;
    if (_seenFacts.length > limits.dedupLimit) {
      _seenFacts.remove(_seenFacts.keys.first);
    }
    sayer.say(v, tag: (id, cause));
    return true;
  }

  /// Drops ids older than the dedup window; the map is in arrival order.
  void _forget<V>(
    LinkedHashMap<String, V> seen,
    DateTime Function(V) at,
    DateTime now,
  ) {
    while (seen.isNotEmpty) {
      final first = seen.entries.first;
      if (now.difference(at(first.value)) < limits.dedupWindow) break;
      seen.remove(first.key);
    }
  }

  // --- Conversations ---------------------------------------------------------

  /// The conversation of each call and fact still remembered, and who set
  /// it going, by its id: what a cause made by hand, naming only its
  /// parent, is found in.
  final LinkedHashMap<String, ({String conversation, Origin origin})>
  _conversations = LinkedHashMap();

  void _converse(String id, String word, Cause cause) {
    _conversations[id] = (
      conversation: cause.conversationOf(id),
      origin: cause.originOf(word),
    );
    if (_conversations.length > limits.dedupLimit) {
      _conversations.remove(_conversations.keys.first);
    }
  }

  /// [cause] in its parent's conversation: one made by hand
  /// (`Cause(by, parent: fact.id)`) names its parent only; the registry
  /// finds the conversation that parent is in, or takes the parent as one
  /// that started it. Who set it going is the parent's to say, as far as
  /// the registry remembers it, never the cause's: a message that follows
  /// from nothing is its own origin, whatever it claims.
  Cause _inConversation(Cause cause) {
    final parent = cause.parent;
    if (parent == null) {
      if (cause.origin == null) return cause;
      return Cause(cause.by, conversation: cause.conversation);
    }
    final known = _conversations[parent];
    final conversation = cause.conversation ?? known?.conversation ?? parent;
    final origin = known?.origin ?? cause.origin;
    if (conversation == cause.conversation && origin == cause.origin) {
      return cause;
    }
    return Cause(
      cause.by,
      parent: parent,
      conversation: conversation,
      origin: origin,
    );
  }

  /// What the registry still remembers of conversation [id] (SPEC §4): its
  /// calls, the changes and the facts committed in it, each in order. The
  /// message that started it is in it, under its own id.
  Conversation conversation(String id) => Conversation(
    id: id,
    calls: [
      for (final c in _recentCalls.values)
        if (c.cause.conversationOf(c.id) == id) c,
    ],
    changes: [
      for (final t in _retained)
        for (final c in t.changes)
          if (c.cause.conversationOf(c.id) == id) c,
    ],
    facts: [
      for (final t in _retained)
        for (final f in t.facts)
          if (f.cause.conversationOf(f.id) == id) f,
    ],
  );

  // --- Use -------------------------------------------------------------------

  late final WordUses _uses = WordUses(
    isWord: (name) {
      final word = canonical(name);
      return _states[word] != null ||
          _commands[word] != null ||
          _facts[word] != null;
    },
    perWord: limits.usersPerWord,
    clock: clock,
  );

  /// Who used [name] (a word, or an old name of one), as it was named:
  /// calls and asks, reads and listeners from outside the build (SPEC
  /// §6.8). What the app's own modules read and watch in this process is
  /// not counted: the compiler knows it. Kept while [name] is a word or an
  /// old name of one; who listens now, beyond.
  List<WordUse> usesOf(String name) => _uses.of(name);

  /// Every name used, and by whom (SPEC §6.8).
  Map<String, List<WordUse>> get usage => _uses.all;

  // --- Built against --------------------------------------------------------

  /// How many words one principal is told built against at most: past
  /// them a peer's made-up names keep nothing.
  static const builtPerPrincipal = BuiltAgainst.perPrincipal;

  /// How many schemas it knows by fingerprint at most, the least recently
  /// told going first (SPEC §25.4).
  static const knownSchemas = BuiltAgainst.knownSchemas;

  late final BuiltAgainst _builtAgainst = BuiltAgainst(
    descriptorOf: (word) => descriptorOf(word),
    aliases: _aliases,
    catalogLog: _catalogLog,
    callLog: _callLog,
    traced: _traced,
  );

  /// Every word a principal's code was built against that is defined
  /// otherwise now, saying where it breaks (SPEC §6.9). What it is told,
  /// it is told as the code is made (a client); the registry judges it
  /// whenever such a word comes, goes or is defined again. Diagnostics
  /// only: nothing waits on it, nothing is refused by it.
  List<Mismatch> get mismatches => _builtAgainst.mismatches;

  /// A [Mismatch] whenever one is found, breaks otherwise, or ends: then
  /// its breaks are empty (the word keeps its promises again, it is gone,
  /// or none built against it is there any more).
  Stream<Mismatch> get mismatchChanges => _builtAgainst.changes;

  // --- Calls -----------------------------------------------------------------

  final LinkedHashMap<String, _Seen> _calls = LinkedHashMap();
  late final CallTraces _trace = CallTraces(
    _callLog,
    on: _traced,
    keep: limits.retainTicks,
  );
  final Map<String, _Guard> _guards = {};
  final StreamController<CallRecord> _records = StreamController.broadcast();
  final StreamController<CallStarted> _starts = StreamController.broadcast();

  late final Journaling _journal = Journaling(epoch: epoch, traces: _trace);

  /// What happened, at the level of use (SPEC §9.3): every call as it
  /// begins and as it ends, refused ones too, every fact said, and every
  /// state written in a conversation, in one order. It keeps nothing: a
  /// host that must not lose it writes it where it lasts. Nothing of it is
  /// made while no one listens.
  Stream<JournalEntry> get journal => _journal.stream;

  final Map<String, CallStarted> _running = {};

  /// Every finished call (SPEC §9).
  Stream<CallRecord> get calls => _records.stream;

  /// Every call whose handler begins, as it begins (SPEC §9); its end comes
  /// on [calls]. A query is not told, as it is not recorded.
  Stream<CallStarted> get callStarts => _starts.stream;

  /// The calls whose handlers run now, oldest first: one that timed out
  /// too, until its handler ends.
  List<CallStarted> get running => List.unmodifiable(_running.values);

  final LinkedHashMap<String, CallRecord> _recentCalls = LinkedHashMap();
  int _recentCallBytes = 0;

  static int _callWeight(CallRecord r) =>
      jsonWeight(r.params) +
      (r.result is CallDone ? jsonWeight((r.result as CallDone).value) : 16);

  // The pairs a dropped tick changed: what explain cannot find may be
  // forgotten rather than never there. Names only; as many as states
  // are ever written.
  final Set<({String state, String? key})> _forgottenChanges = {};
  bool _forgotCalls = false;

  void _remember(CallRecord record) {
    // A late end takes the place of the record of its timeout.
    if (_recentCalls.remove(record.id) case final before?) {
      _recentCallBytes -= _callWeight(before);
    }
    _recentCalls[record.id] = record;
    _recentCallBytes += _callWeight(record);
    _journal.ended(record);
    while (_recentCalls.length > limits.retainTicks ||
        (_recentCalls.length > 1 && _recentCallBytes > limits.retainBytes)) {
      final first = _recentCalls.keys.first;
      _recentCallBytes -= _callWeight(_recentCalls.remove(first)!);
      _forgotCalls = true;
    }
    _records.add(record);
  }

  /// A finished call still remembered (as many as ticks are retained), by
  /// its id: what a cause's parent leads to.
  CallRecord? callRecord(String id) => _recentCalls[id];

  /// Why [state] (of [key]) is as it is: its value, its last change still
  /// retained (when, on whose behalf, through what), and the calls that led
  /// to it, nearest first, as far as they are remembered: at most ten, and
  /// [Explanation.trailCut] says the trail goes further back than given.
  Explanation explain(String state, {String? key}) {
    state = canonical(state);
    final change = lastChange(state, key: key);
    final trail = <CallRecord>[];
    var parent = change?.cause.parent;
    var cut = false;
    final seen = <String>{};
    while (parent != null && seen.add(parent)) {
      if (trail.length >= 10) {
        // The trail goes on past these: said so, not given as if these
        // ten were all of it.
        cut = true;
        break;
      }
      final call = callRecord(parent);
      if (call == null) {
        cut = _forgotCalls;
        break;
      }
      trail.add(call);
      parent = call.cause.parent;
    }
    return Explanation(
      state: state,
      key: key,
      value: read(state, key: key),
      change: change,
      forgotten: change == null &&
          _forgottenChanges.contains((state: state, key: key)),
      trail: trail,
      trailCut: cut,
    );
  }

  /// The last committed change of [state] (of [key]) still retained, or
  /// null: with its cause, it says why the state is as it is.
  StateChange? lastChange(String state, {String? key}) {
    state = canonical(state);
    for (final t in _retained.toList().reversed) {
      for (final c in t.changes.reversed) {
        if (c.state == state && c.key == key) return c;
      }
    }
    return null;
  }

  Future<CallResult<Object?>> _run(
    String id,
    String command,
    Kept rawParams,
    Cause cause, {
    bool record = true,
    CancellationToken? cancel,
  }) async {
    final started = clock.now();
    var params = rawParams;

    CallResult<Object?> finish(CallResult<Object?> r, {bool late = false}) {
      if (r is CallDone<Object?>) _builtAgainst.answered(command, cause.by, r);
      if (r case CallRefused(:final code, why: final reason, :final guard)) {
        if (_callLog.isEnabled(RpcLogLevel.info)) {
          _callLog.info(
            'refused',
            data: {
              'command': command,
              'code': code.name,
              'id': id,
              'conversation': cause.conversationOf(id),
              'by': cause.by.selector,
              'origin': cause.originOf(command).word,
              'originBy': cause.originOf(command).by.selector,
              'reason': reason,
              'guard': ?guard,
            },
          );
        }
      }
      if (record && !_records.isClosed) {
        _remember(
          keptRecord(
            id: id,
            command: command,
            params: params,
            cause: cause,
            result: r,
            started: started,
            finished: clock.now(),
            late: late,
          ),
        );
      }
      return r;
    }

    final entry = _commands[command];
    if (entry == null) {
      return finish(CallRefused(Refusal.unknownCommand, 'no command $command'));
    }
    final d = entry.descriptor;
    try {
      params = _admitParams(
        entry.params,
        _builtAgainst.adapted(command, entry.descriptor, rawParams, cause.by),
      );
    } on TypeMismatch catch (e) {
      return finish(CallRefused(Refusal.invalidParams, '$e'));
    }
    if (!d.callers.allows(cause.by)) {
      return finish(
        CallRefused(Refusal.notPermitted, '${cause.by} may not call $command'),
      );
    }
    if (entry.whyNot?.call() case final why?) {
      return finish(CallRefused(Refusal.unavailable, why));
    }
    // The guards are judged here, not in a method of their own: with none
    // asked, nothing is awaited before the handler runs, and an await of
    // even a method with nothing to wait for would let other work in first
    // (the journal's order would show it).
    final pending = PendingCall._kept(id, d, params, cause);
    var asked = false;
    for (final g in [..._guards.values]) {
      String? why;
      // One that judges no call of this command is not asked: nothing to
      // wait for, and the handler still begins as the call is made.
      if (g.judges case final j? when !j(command)) continue;
      if (g.ask case final ask?) {
        asked = true;
        // Asked across a connection: no answer in time, or none at all,
        // denies, since the one who keeps the rule could not say.
        try {
          // Its caller's cancel ends the wait: the call does not run.
          why = await untilCancelled(
            ask(pending).timeout(g.timeout!),
            cancel,
            () => null,
          );
          if (cancel?.isCancelled ?? false) {
            return finish(const CallCancelled());
          }
        } on Object catch (e) {
          why = 'its guard ${g.id} could not be asked: $e';
          if (_callLog.isEnabled(RpcLogLevel.warning)) {
            _callLog.warning(
              'guard could not be asked',
              error: e,
              data: {'guard': g.id, 'command': command, 'id': id},
            );
          }
        }
      } else {
        try {
          why = g.check!(pending);
        } catch (e, s) {
          // A guard that cannot judge denies, as one asked across a
          // connection that cannot answer does: the rule it keeps holds.
          why = 'its guard ${g.id} failed: $e';
          _onError(e, s);
        }
      }
      if (why == null) continue;
      return finish(CallRefused(Refusal.denied, why, guard: g.id));
    }

    // An asked guard may take a while: the command may be gone by now, or
    // unable to run.
    if (_commands[command] != entry) {
      return finish(CallRefused(Refusal.unknownCommand, '$command is gone'));
    }
    if (asked) {
      if (entry.whyNot?.call() case final why?) {
        return finish(CallRefused(Refusal.unavailable, why));
      }
    }
    // Cancelled before its handler began: it does not run.
    if (cancel?.isCancelled ?? false) return finish(const CallCancelled());

    CallResult<Object?> answered(Object? answer) {
      if (entry.returns case final t?) {
        try {
          return keptDone(
            Kept(t.check(answer, this), t is JsonValue ? null : t),
          );
        } on TypeMismatch catch (e) {
          return CallFailed('returned a wrong value: $e');
        }
      }
      return const CallDone(null);
    }

    final expired = CancellationToken();
    final span = _trace.open(id, command, params, cause, query: entry.query);
    final returns = entry.returns;
    final served = CommandCall._kept(
      id,
      command,
      params,
      cause,
      expired,
      returns is JsonValue ? null : returns,
      span: span,
    );
    if (record) {
      final s = keptStarted(
        id: id,
        command: command,
        params: params,
        cause: cause,
        started: started,
      );
      _running[id] = s;
      if (!_starts.isClosed) _starts.add(s);
      _journal.started(s);
    }
    final work = Future.sync(
      () => entry.query
          ? asQuery(command, () => entry.local.call(served))
          : entry.local.call(served),
    );
    // The handler goes on after its caller stopped waiting: its end is
    // recorded as late, and a retry with the call's id waits for it, not
    // for why this caller stopped.
    CallResult<Object?> stop(CallResult<Object?> why, String event) {
      expired.cancel();
      span.event(event, level: RpcLogLevel.warning);
      final late = work.then(
        answered,
        onError: (Object e, StackTrace s) => _ended(id, e, s),
      );
      unawaited(
        late.then((r) {
          _running.remove(id);
          _trace.close(id, span, r, late: true, query: entry.query);
          finish(r, late: true);
        }),
      );
      if (_calls[id] case final c?) c.result = late;
      return why;
    }

    CallResult<Object?> result;
    try {
      // What the caller's cancel says, once it came: a mark, as a handler's
      // answer can be anything.
      final first = await untilCancelled<Object?>(
        work,
        cancel,
        () => _cancelledMark,
      ).timeout(d.deadline);
      result = identical(first, _cancelledMark)
          ? stop(const CallCancelled(), 'cancelled')
          : answered(first);
    } on TimeoutException {
      result = stop(const CallTimedOut(), 'timed out');
    } catch (e, s) {
      result = _ended(id, e, s);
    }
    if (result is! CallTimedOut && result is! CallCancelled) {
      _running.remove(id);
      _trace.close(id, span, result, query: entry.query);
    }
    return finish(result);
  }

  /// How a call [id] whose handler threw [e] ended: `lost` when its answer
  /// could not come back ([AnswerLost]), else `failed`.
  static CallResult<Object?> _ended(String id, Object e, StackTrace s) =>
      e is AnswerLost ? CallLost(id, e.how) : CallFailed(e, s);

  // --- Lifetime --------------------------------------------------------------

  /// What goes before the registry does, the last given first: its
  /// participants and their sessions ([RawRegistry.beforeDispose]).
  final List<void Function()> _beforeDispose = [];
  bool _disposing = false;

  /// Ends every participant and session of it, the last made first, so
  /// their words, owners and connections go with it; then closes the
  /// streams and stops the timers.
  Future<void> dispose() async {
    if (_disposing) return;
    _disposing = true;
    for (final f in _beforeDispose.reversed) {
      try {
        f();
      } on Object catch (e, st) {
        _onError(e, st);
      }
    }
    _beforeDispose.clear();
    await Future.wait([
      _ticks.close(),
      _availability.close(),
      _hub.dispose(),
      _catalog.close(),
      _builtAgainst.dispose(),
      _records.close(),
      _starts.close(),
      _journal.close(),
    ]);
  }
}
