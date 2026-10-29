import 'dart:async';
import 'dart:collection';

import 'package:clock/clock.dart' as clock_zone;
import 'package:clock/clock.dart' show Clock;
import 'package:rpc_dart/logger.dart';

import '../core/core.dart';

export 'package:rpc_dart/logger.dart'
    show LogScope, LogSpanHandle, LogSpanStatus, RpcLogLevel;
export '../core/core.dart'
    show
        Disposer,
        ICommandCaller,
        IFactEmitter,
        IFactListener,
        IHandle,
        IStateReader,
        IStateWriter;

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

/// Serves a command: answers its result (checked against `returns`), or
/// throws.
///
/// Returns `dynamic` so a handler that answers nothing needs no `return`.
typedef CommandHandler = FutureOr<dynamic> Function(CommandCall call);

/// Null when a command can run now, else why not (SPEC §6.2). Synchronous;
/// reads committed state.
typedef Availability = String? Function();

/// Null when [call] may go on, else why not (SPEC §10). Synchronous; reads
/// committed state; makes no calls.
typedef GuardCheck = String? Function(PendingCall call);

/// Where errors of guards and timers go.
typedef ErrorSink = void Function(Object error, StackTrace stack);

/// What a query's handler tried that would change something (SPEC §6.6):
/// a write, a fact, a command. Thrown where it was tried, so the
/// query ends `failed` and nothing changed.
final class QueryEffect extends StateError {
  QueryEffect(this.query, this.tried)
    : super('$query is a query, it changes nothing: it tried to $tried');

  final String query;
  final String tried;
}

const Symbol _asking = #parlance.asking;

/// Runs [body] as the handler of [query]: what it does through parlance,
/// at once or later (after an await, in a timer it started), is told to
/// be the query's, and refused when it would change something. Closures
/// still see everything they captured: what they try is refused, not
/// hidden. A remote participant serves its queries the same way.
R asQuery<R>(String query, R Function() body) =>
    runZoned(body, zoneValues: {_asking: query});

/// The query whose handler the code running now is ([asQuery]); null
/// outside one.
String? answeringQuery() => Zone.current[_asking] as String?;

/// Throws [QueryEffect] when the code running now is a query's handler
/// ([asQuery]): [tried] is what it would have done.
void refuseInQuery(String tried) {
  if (answeringQuery() case final query?) throw QueryEffect(query, tried);
}

/// A call being served: what a handler gets. The registry makes it; a
/// remote participant (SPEC §22.4) makes it of what the host sent.
final class CommandCall {
  CommandCall(
    this.id,
    this.command,
    Map<String, Object?> params,
    this.cause,
    this.expired, {
    LogSpanHandle? span,
  }) : _params = Kept.json(params),
       _answers = null,
       _span = span;

  CommandCall._kept(
    this.id,
    this.command,
    this._params,
    this.cause,
    this.expired,
    this._answers, {
    LogSpanHandle? span,
  }) : _span = span;

  final String id;
  final String command;

  /// As the command keeps them (SPEC §18).
  final Kept _params;

  /// The shape the answer is kept by, when the command keeps it as it is:
  /// then the handler answers the Dart value, else its JSON.
  final Shape<Object?>? _answers;

  /// Checked, with defaults filled; as JSON.
  Map<String, Object?> get params => _params.json! as Map<String, Object?>;
  final Cause cause;

  Principal get by => cause.by;

  /// Completes when the deadline passes: the caller was answered
  /// `timedOut`. What the handler does after still stands (and its end is
  /// recorded as late), so a handler that can stop stops here.
  final Future<void> expired;

  /// The cause of what the handler does on behalf of [by]: nested calls
  /// and writes. Its parent is this call.
  Cause causeFor(Principal by) => cause.child(id, by: by, word: command);

  /// The span of this call in the registry's log (SPEC §9.2): what the
  /// handler logs in it, events and spans of its own, goes with the call
  /// and its trace. Without a log it is `LogScope.noop`'s, ended and
  /// keeping nothing; an event whose message or data costs something is
  /// built behind `span.isEnabled(level)`, false then.
  LogSpanHandle get span => _span ?? noSpan;
  final LogSpanHandle? _span;
}

/// The params of [call] as [shape] has them: the value itself when the
/// command keeps them by [shape], else their JSON decoded. The package's
/// own.
T paramsAs<T>(CommandCall call, Shape<T> shape) => call._params.asShape(shape);

/// Whether [call]'s handler answers the Dart value of [shape]: when the
/// command keeps its answer by it; else it answers JSON. The package's
/// own.
bool answersAs(CommandCall call, Shape<Object?>? shape) =>
    identical(call._answers, shape);

/// A call on its way, as guards see it.
final class PendingCall {
  PendingCall(this.id, this.command, Map<String, Object?> params, this.cause)
    : _params = Kept.json(params);

  PendingCall._kept(this.id, this.command, this._params, this.cause);

  final String id;

  /// The command's, or the query's, descriptor.
  final CallableDescriptor command;
  final Kept _params;

  /// Its params, checked, as JSON: made when a guard reads them.
  Map<String, Object?> get params => _params.json! as Map<String, Object?>;
  final Cause cause;

  Principal get by => cause.by;
}

/// A change in the catalog (SPEC §6.4).
sealed class CatalogChange {
  const CatalogChange();
}

final class DescriptorAdded extends CatalogChange {
  const DescriptorAdded(this.descriptor);
  final Descriptor descriptor;
}

final class DescriptorRemoved extends CatalogChange {
  const DescriptorRemoved(this.descriptor);
  final Descriptor descriptor;
}

/// Entity kinds came, went or their entities changed.
final class KindChanged extends CatalogChange {
  const KindChanged(this.kind);
  final String kind;
}

/// A word's old name came or went (SPEC §6.4).
final class AliasChanged extends CatalogChange {
  const AliasChanged(this.alias);
  final String alias;
}

/// The only write handle of a state: the registry's own, or a remote
/// participant's (SPEC §22).
abstract interface class IStateHandle implements IHandle {
  StateDescriptor get descriptor;

  /// The shape whose Dart values [set] takes as they are (SPEC §18); null:
  /// it takes JSON.
  Shape<Object?>? get shape;

  /// Writes [value] (of [key] for a keyed state).
  void set(Object? value, {String? key, Cause? cause});

  void remove({String? key, Cause? cause});
}

/// An emit handle of a fact: the registry's own, or a remote participant's
/// (SPEC §22).
abstract interface class IFactHandle implements IHandle {
  FactDescriptor get descriptor;

  /// The shape whose Dart values [emit] takes as they are (SPEC §18); null:
  /// it takes JSON.
  Shape<Object?>? get shape;

  /// Says [payload]; false when [id] was said already.
  bool emit(Object? payload, {String? id, Cause? cause});
}

/// The only write handle of a state.
final class RawStateWriter implements IStateHandle {
  RawStateWriter._(this._r, this.descriptor, this.by, this.shape);

  final Registry _r;
  @override
  final StateDescriptor descriptor;

  @override
  final Shape<Object?>? shape;

  /// Who writes, for the causes of its writes.
  final Principal by;
  bool _disposed = false;

  /// Sets the value (of [key], for a keyed state).
  ///
  /// A write a handler makes passes [cause] (`call.causeFor(by)`), so it
  /// follows from the call; without it, the write starts a new chain.
  @override
  void set(Object? value, {String? key, Cause? cause}) {
    _live();
    _r._writeState(
      descriptor,
      key,
      value,
      cause ?? Cause(by),
      asIs: shape != null,
    );
  }

  /// Removes the value (of [key]).
  @override
  void remove({String? key, Cause? cause}) {
    _live();
    _r._removeState(descriptor, key, cause ?? Cause(by));
  }

  void _live() {
    if (_disposed) throw StateError('${descriptor.name} is gone');
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _r._undefine(descriptor.name);
  }
}

/// An emit handle of a fact.
final class RawFactEmitter implements IFactHandle {
  RawFactEmitter._(
    this._r,
    this.descriptor,
    this.by,
    this._emitter, {
    required this.definer,
    this.shape,
  });

  final Registry _r;
  final LocalFactEmitter<Object?> _emitter;
  @override
  final FactDescriptor descriptor;

  @override
  final Shape<Object?>? shape;

  /// The producer, for the causes of its facts.
  final Principal by;

  /// Disposing this handle removes the fact from the catalog.
  final bool definer;
  bool _disposed = false;

  /// Emits [payload]. A fact whose [id] was seen within the dedup window is
  /// dropped; returns whether it was taken.
  @override
  bool emit(Object? payload, {String? id, Cause? cause}) {
    if (_disposed) throw StateError('${descriptor.name} is gone');
    return _r._emit(
      descriptor,
      _emitter,
      payload,
      id ?? newId(),
      cause ?? Cause(by),
      asIs: shape != null,
    );
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _emitter.dispose();
    if (definer) _r._undefine(descriptor.name);
  }
}

final class _StateEntry {
  _StateEntry(this.descriptor, this.local, this.shape) : writer = local.claim();
  final StateDescriptor descriptor;

  /// How its values are checked, kept and told as JSON (SPEC §18).
  final Shape<Object?> shape;

  /// The JSON last told of each key's value, beside the value it is of:
  /// made when asked, once a value.
  final Map<String?, (Object?, Object?)> _json = {};

  /// The JSON of [kept], the value of [key].
  Object? jsonOf(String? key, Object? kept) {
    if (kept == null || shape is JsonValue) return kept;
    if (_json[key] case (final of, final json) when identical(of, kept)) {
      return json;
    }
    final json = freezeJson(shape.toJson(kept));
    _json[key] = (kept, json);
    return json;
  }

  /// Its values by key, null for an unkeyed state; the registry is the
  /// local state's only writer.
  final LocalKeyedState<String?, Object?> local;
  final LocalKeyedStateWriter<String?, Object?> writer;
}

final class _CommandEntry {
  _CommandEntry(
    this.descriptor,
    this.local,
    this.serving,
    this.available, {
    Shape<Object?>? params,
    Shape<Object?>? returns,
  }) : params = params != null && params.keptAsIs
           ? params
           : JsonValue(descriptor.params),
       returns = switch (descriptor.returns) {
         null => null,
         final t =>
           returns != null && returns.keptAsIs ? returns : JsonValue(t),
       };

  /// How its params and its answer are checked and kept (SPEC §18).
  final Shape<Object?> params;
  final Shape<Object?>? returns;

  /// A command's or a query's: both are called through the same stages.
  final CallableDescriptor descriptor;

  bool get query => descriptor is QueryDescriptor;
  final LocalCommand<CommandCall, Object?> local;
  final IHandle serving;
  final Availability? available;
}

final class _FactEntry {
  _FactEntry(this.descriptor, this.local, this.shape);
  final FactDescriptor descriptor;

  /// How its payloads are checked, kept and told as JSON (SPEC §18).
  final Shape<Object?> shape;

  /// Its payloads, tagged with their id and cause.
  final LocalFact<Object?> local;
}

final class _Guard {
  _Guard(this.id, this.check, this.overridable) : ask = null, timeout = null;
  _Guard.asked(this.id, this.ask, this.overridable, this.timeout)
    : check = null;
  final String id;
  final GuardCheck? check;

  /// A guard another judges, across a connection.
  final Future<String?> Function(PendingCall call)? ask;
  final Duration? timeout;
  final bool overridable;
}

/// The registry: the vocabulary, its values, calls, guards and the feed (SPEC §§5–12).
///
/// One isolate, one writer: every commit happens here in order, so seq is a
/// total order. Participants hold handles and never each other.
final class Registry implements ITypeContext {
  Registry({
    this.dedupWindow = const Duration(minutes: 10),
    this.retainTicks = 1000,
    this.recentPerFact = 100,
    this.usersPerWord = 64,
    this.dedupLimit = 10000,
    this.retainBytes = 4 << 20,
    Set<String> overriders = const {},
    Clock? clock,
    ErrorSink? onError,
    LogScope? log,
  }) : clock = clock ?? clock_zone.clock,
       overriders = Set.unmodifiable(overriders),
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

  /// How long ids of calls and facts are remembered to drop repeats.
  final Duration dedupWindow;

  /// How many ids of calls, and of facts, are remembered at most within
  /// [dedupWindow]: past it the oldest go, so a burst of calls (a fader
  /// dragged) does not hold ten minutes of them. A retry of one forgotten
  /// runs again.
  final int dedupLimit;

  /// How many ticks a feed can resume from.
  final int retainTicks;

  /// How many facts of each name [recent] keeps.
  final int recentPerFact;

  /// How many principals [usesOf] tells apart for one word; past them a
  /// use is counted under the principal's kind alone (`guest`), so many
  /// guests do not grow it, and no use goes unseen.
  final int usersPerWord;

  /// About how many bytes of values each history keeps: the retained ticks,
  /// the call records, the recent facts of each name. Whichever bound comes
  /// first, this or the count, drops the oldest, and the newest is
  /// always kept, however big; a feed behind what is kept
  /// resumes from a snapshot. Values are weighed as their JSON, roughly.
  final int retainBytes;

  /// The principal kinds that may override a guard's overridable denial.
  final Set<String> overriders;

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

  final Map<String, EntityKind> _kinds = {};
  final Map<String, String? Function(Object?)> _customTypes = {};
  final Map<String, _StateEntry> _states = {};
  final Map<String, _CommandEntry> _commands = {};
  final Map<String, _FactEntry> _facts = {};

  /// The word each local state and fact holds.
  final Map<Object, String> _names = Map.identity();

  /// The shape each local state and fact keeps its values by.
  final Map<Object, Shape<Object?>> _shapeOf = Map.identity();
  final StreamController<CatalogChange> _catalog = StreamController.broadcast();

  void _announce(CatalogChange c) {
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
      case KindChanged(:final kind):
        if (_catalogLog.isDebug) {
          _catalogLog.debug('kind changed', data: {'kind': kind});
        }
    }
    if (!_catalog.isClosed) _catalog.add(c);
  }

  /// Additions, removals and entity changes, in order.
  Stream<CatalogChange> get catalogChanges => _catalog.stream;

  final StreamController<String> _availability = StreamController.broadcast();

  /// Commands whose availability check would answer otherwise now, though
  /// no tick says so: an owner across a connection told it, or one whose
  /// check reads what the registry does not keep.
  Stream<String> get availabilityChanges => _availability.stream;

  /// Every descriptor there is now.
  List<Descriptor> get catalog => [
    for (final s in _states.values) s.descriptor,
    for (final c in _commands.values) c.descriptor,
    for (final f in _facts.values) f.descriptor,
  ];

  Iterable<EntityKind> get kinds => _kinds.values;

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
  /// answers its first result, the descriptors and the entity kinds.
  Map<String, Object?> describe() => {
    'epoch': epoch,
    'seq': seq,
    'dedupWindowMs': dedupWindow.inMilliseconds,
    'descriptors': [for (final d in catalog) d.toJson()],
    'kinds': [for (final k in _kinds.values) k.toJson()],
    if (_aliases.isNotEmpty) 'aliases': Map.of(_aliases),
  };

  List<String> _unreadable(Principal by) => [
    for (final s in _states.values)
      if (!(s.descriptor.readers?.allows(by) ?? true)) s.descriptor.name,
    for (final f in _facts.values)
      if (!(f.descriptor.readers?.allows(by) ?? true)) f.descriptor.name,
  ];

  /// Registers the host's type [name] with its checker (SPEC §2).
  IHandle registerType(String name, String? Function(Object? value) check) {
    checkName(name, 'type');
    if (_customTypes.containsKey(name)) throw StateError('type $name exists');
    _customTypes[name] = check;
    return Disposer(() => _customTypes.remove(name));
  }

  @override
  bool hasKind(String kind) => _kinds.containsKey(kind);

  @override
  bool hasEntity(String kind, String id) => _kinds[kind]?.contains(id) ?? false;

  @override
  String? checkCustom(String name, Object? value) {
    final check = _customTypes[name];
    if (check == null) return 'no type $name';
    return check(value);
  }

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

  final Map<String, String> _aliases = {};

  /// The old names of words, each with the name it stands for now.
  Map<String, String> get aliases => Map.unmodifiable(_aliases);

  /// The name [name] stands for: the word it was renamed to, or itself.
  String canonical(String name) => _aliases[name] ?? name;

  /// Makes [old] another name of the word [now] (SPEC §6.4): a word
  /// renamed goes on answering to its old name, in calls, reads and facts,
  /// so what names it (a plugin, an agent, a stored call) keeps working.
  /// `describe` lists it under `aliases`. Dispose the handle to drop it.
  IHandle alias(String old, String now) {
    checkWordName(old, 'old');
    final target = canonical(now);
    if (_states.containsKey(old) ||
        _commands.containsKey(old) ||
        _facts.containsKey(old)) {
      throw StateError('$old is a word itself');
    }
    if (_aliases.containsKey(old)) {
      throw StateError('$old is an old name of ${_aliases[old]} already');
    }
    if (target == old) throw StateError('$old cannot stand for itself');
    _aliases[old] = target;
    // Old names of [old] now stand for its new one.
    for (final e in _aliases.entries.toList()) {
      if (e.value == old) _aliases[e.key] = target;
    }
    _announce(AliasChanged(old));
    return Disposer(() {
      if (_aliases.remove(old) == null) return;
      _uses.forget(old);
      _announce(AliasChanged(old));
    });
  }

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
  final ListQueue<Tick> _retained = ListQueue();
  final ListQueue<int> _retainedWeights = ListQueue();
  int _retainedBytes = 0;
  final Map<String, _RecentFacts> _recent = {};

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
    int weigh(Object of, Object? v) => v == null ? 8 : _shapeOf[of]!.weigh(v);
    var weight = 0;
    final factWeights = <int>[];
    for (final c in t.changes) {
      // The JSON told of a value that changed is of the value before.
      final state = _states[_names[c.state]];
      if (state != null && identical(state.local, c.state)) {
        state._json.remove(c.key);
      }
      weight += weigh(c.state, c.value) + weigh(c.state, c.previous);
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
    while (_retained.length > retainTicks ||
        (_retained.length > 1 && _retainedBytes > retainBytes)) {
      _retained.removeFirst();
      _retainedBytes -= _retainedWeights.removeFirst();
      _forgotTicks = true;
    }
    for (final (i, f) in committed.indexed) {
      final q = _recent.putIfAbsent(f.fact, _RecentFacts.new);
      q.add(f, factWeights[i]);
      while (q.length > recentPerFact ||
          (q.length > 1 && q.bytes > retainBytes)) {
        q.removeFirst();
      }
    }
    if (!_ticks.isClosed) _ticks.add(tick);
  }

  // --- Reading ---------------------------------------------------------------

  /// Who watches which state (of which key), each with the seq it read
  /// at: a change reaches only its own watchers, however many watch other
  /// states, and only those that read before it.
  final Map<(String, String?), Map<StreamController<Object?>, int>> _watchers =
      {};
  StreamSubscription<Tick>? _watching;

  /// What each watcher is told of a change it follows: its JSON, or the
  /// value as the watcher's shape has it.
  final Map<StreamController<Object?>, Object? Function(StateChange)> _tell =
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
    _watching = null;
  }

  void _toWatchers(Tick t) {
    for (final c in t.changes) {
      final set = _watchers[(c.state, c.key)];
      if (set == null) continue;
      for (final e in [...set.entries]) {
        if (c.seq > e.value) e.key.add(_tell[e.key]!(c));
      }
    }
  }

  // --- Facts -----------------------------------------------------------------

  final LinkedHashMap<String, DateTime> _seenFacts = LinkedHashMap();

  bool _emit(
    FactDescriptor d,
    LocalFactEmitter<Object?> emitter,
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
    if (_seenFacts.length > dedupLimit) {
      _seenFacts.remove(_seenFacts.keys.first);
    }
    emitter.emit(v, tag: (id, cause));
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
      if (now.difference(at(first.value)) < dedupWindow) break;
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
    if (_conversations.length > dedupLimit) {
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
    perWord: usersPerWord,
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
    keep: retainTicks,
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

  // Whether retention dropped ticks or call records: what explain cannot
  // find may be forgotten rather than never there.
  bool _forgotTicks = false;
  bool _forgotCalls = false;

  void _remember(CallRecord record) {
    // A late end takes the place of the record of its timeout.
    if (_recentCalls.remove(record.id) case final before?) {
      _recentCallBytes -= _callWeight(before);
    }
    _recentCalls[record.id] = record;
    _recentCallBytes += _callWeight(record);
    _journal.ended(record);
    while (_recentCalls.length > retainTicks ||
        (_recentCalls.length > 1 && _recentCallBytes > retainBytes)) {
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
  /// to it, nearest first, as far as they are remembered.
  Explanation explain(String state, {String? key}) {
    state = canonical(state);
    final change = lastChange(state, key: key);
    final trail = <CallRecord>[];
    var parent = change?.cause.parent;
    var cut = false;
    final seen = <String>{};
    while (parent != null && seen.add(parent) && trail.length < 10) {
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
      forgotten: change == null && _forgotTicks,
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
    required bool override,
    bool record = true,
  }) async {
    final started = clock.now();
    final overridden = <String>[];
    var params = rawParams;

    CallResult<Object?> finish(CallResult<Object?> r, {bool late = false}) {
      if (r case CallRefused(:final code, :final reason, :final guard)) {
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
            overridden: overridden,
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
    if (entry.available?.call() case final why?) {
      return finish(CallRefused(Refusal.unavailable, why));
    }
    final pending = PendingCall._kept(id, d, params, cause);
    var asked = false;
    for (final g in [..._guards.values]) {
      String? why;
      if (g.ask case final ask?) {
        asked = true;
        // Asked across a connection: no answer in time, or none at all,
        // denies, since the one who keeps the rule could not say.
        try {
          why = await ask(pending).timeout(g.timeout!);
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
      if (override && g.overridable && overriders.contains(cause.by.kind)) {
        overridden.add(g.id);
        continue;
      }
      return finish(
        CallRefused(
          Refusal.denied,
          why,
          guard: g.id,
          overridable: g.overridable,
        ),
      );
    }

    // An asked guard may take a while: the command may be gone by now, or
    // unable to run.
    if (_commands[command] != entry) {
      return finish(CallRefused(Refusal.unknownCommand, '$command is gone'));
    }
    if (asked) {
      if (entry.available?.call() case final why?) {
        return finish(CallRefused(Refusal.unavailable, why));
      }
    }

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

    final expired = Completer<void>();
    final span = _trace.open(id, command, params, cause, query: entry.query);
    final returns = entry.returns;
    final served = CommandCall._kept(
      id,
      command,
      params,
      cause,
      expired.future,
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
    CallResult<Object?> result;
    try {
      result = answered(await work.timeout(d.deadline));
    } on TimeoutException {
      result = const CallTimedOut();
      expired.complete();
      span.event('timed out', level: RpcLogLevel.warning);
      // The handler goes on: its end is recorded as late, and a retry with
      // the call's id answers it.
      unawaited(
        work.then(answered, onError: (Object e) => CallFailed(e)).then((r) {
          if (_calls[id] case final c?) {
            c.result = Future.value(r);
          }
          _running.remove(id);
          _trace.close(id, span, r, late: true, query: entry.query);
          finish(r, late: true);
        }),
      );
    } catch (e) {
      result = CallFailed(e);
    }
    if (result is! CallTimedOut) {
      _running.remove(id);
      _trace.close(id, span, result, query: entry.query);
    }
    return finish(result);
  }

  // --- Lifetime --------------------------------------------------------------

  /// Closes the streams and stops the timers.
  Future<void> dispose() async {
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

/// What the registry does on behalf of whoever it is told (SPEC §22):
/// defines words with no vocabulary to keep them in, calls and writes as
/// any principal, guards every command. The package's own, for what it
/// builds on the registry (participants, sessions, views, tests); not
/// exported, so a host's code reaches the registry through participants
/// only, as the one each part is.
extension RawRegistry on Registry {
  /// [command]'s availability may have changed without a tick (SPEC §6.5).
  void availabilityChanged(String command) {
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
    final kept = shape != null && shape.keptAsIs ? shape : null;
    final keep = kept ?? JsonValue(d.type);
    final local = LocalFact<Object?>(hub: _hub, open: d.open);
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

  /// Another emit handle of an open fact, for producer [by]. The host
  /// decides who gets one. It takes Dart values when its [shape] is the
  /// one the fact keeps its payloads by, else JSON.
  RawFactEmitter producer(
    String fact, {
    required Principal by,
    Shape<Object?>? shape,
  }) {
    final f = _facts[canonical(fact)];
    if (f == null) throw StateError('no fact $fact');
    final d = f.descriptor;
    if (!d.open) throw StateError('$fact is not open');
    return RawFactEmitter._(
      this,
      d,
      by,
      f.local.claim(),
      definer: false,
      shape: identical(shape, f.shape) ? shape : null,
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
        : decodeWith(shape, e.jsonOf(key, v));
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
    return identical(kept, _other) ? decodeWith(shape, c.value) : kept as T?;
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
    state = canonical(state);
    final at = (state, key);
    late StreamController<V?> out;
    out = StreamController<V?>(
      onListen: () {
        out.add(now());
        _tell[out] = of;
        // Ticks committed before it read are on their way to the others'
        // listener still: what it read is newer than they are.
        (_watchers[at] ??= {})[out] = seq;
        _watching ??= ticks.listen(_toWatchers, onDone: _endWatchers);
      },
      onCancel: () {
        _tell.remove(out);
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

  /// The facts of [fact] as [shape] has their payloads (SPEC §18).
  Stream<(T, FactMessage)> factsAs<T>(String fact, Shape<T> shape) =>
      facts(fact: fact).map((m) => (_payloadAs(m, shape), m));

  /// Facts as they are committed, of [fact] only when given.
  Stream<FactMessage> facts({String? fact}) {
    final name = fact == null ? null : canonical(fact);
    return ticks.expand(
      (t) => name == null ? t.facts : t.facts.where((f) => f.fact == name),
    );
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
  FactMessage? recentFact(String id) {
    for (final q in _recent.values) {
      for (final m in q._q) {
        if (m.id == id) return m;
      }
    }
    return null;
  }

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
    bool override = false,
    Cause? cause,
  }) => callKept(
    command,
    Kept.json(params),
    by: by,
    id: id,
    override: override,
    cause: cause,
  );

  /// [call] with [params] as their shape has them (SPEC §18): a command
  /// that keeps its params by that shape takes them as they are.
  Future<CallResult<Object?>> callKept(
    String command,
    Kept params, {
    required Principal by,
    String? id,
    bool override = false,
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
      return _run(
        callId,
        command,
        params,
        cause,
        override: override,
        record: false,
      );
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
    final result = _run(callId, command, params, cause, override: override);
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
  IHandle addGuard(String id, GuardCheck check, {bool overridable = true}) {
    if (_guards.containsKey(id)) throw StateError('guard $id exists');
    final g = _Guard(id, check, overridable);
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
    bool overridable = true,
    Duration timeout = const Duration(seconds: 2),
  }) {
    if (_guards.containsKey(id)) throw StateError('guard $id exists');
    final g = _Guard.asked(id, ask, overridable, timeout);
    _guards[id] = g;
    return Disposer(() {
      if (_guards[id] == g) _guards.remove(id);
    });
  }
}

/// A call id seen within the dedup window, and the call it was given for.
final class _Seen {
  _Seen(this.at, this.command, this.params, this.by, this.result);
  final DateTime at;
  final String command;
  final Kept params;
  final Principal by;
  Future<CallResult<Object?>> result;
}

/// The recent facts of one name, and about how much they weigh.
final class _RecentFacts {
  final ListQueue<FactMessage> _q = ListQueue();
  final ListQueue<int> _weights = ListQueue();
  int bytes = 0;

  int get length => _q.length;

  void add(FactMessage f, int weight) {
    _q.add(f);
    _weights.add(weight);
    bytes += weight;
  }

  void removeFirst() {
    _q.removeFirst();
    bytes -= _weights.removeFirst();
  }

  List<FactMessage> toList() => _q.toList();
}
