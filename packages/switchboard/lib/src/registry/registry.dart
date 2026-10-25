import 'dart:async';
import 'dart:collection';

import 'package:clock/clock.dart' as clock_zone;
import 'package:clock/clock.dart' show Clock;

import '../core/core.dart';

export '../core/core.dart'
    show
        CommandCaller,
        FactEmitter,
        FactListener,
        Handle,
        StateReader,
        StateWriter;

import 'cause.dart';
import 'descriptors.dart';
import 'ids.dart';
import 'json.dart';
import 'messages.dart';
import 'types.dart';

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

/// Runs before an interceptable command (SPEC §11). [cause] is for the
/// calls the hook makes: the intercepted call is its parent and the hook's
/// id is in its chain, so the hook never intercepts its own calls.
typedef BeforeHook = Future<void> Function(PendingCall call, Cause cause);

/// Where errors of guards, hooks and timers go.
typedef ErrorSink = void Function(Object error, StackTrace stack);

/// A call being served: what a handler gets.
final class CommandCall {
  const CommandCall._(
    this.id,
    this.command,
    this.params,
    this.cause,
    this.expired,
  );

  final String id;
  final String command;

  /// Checked, with defaults filled.
  final Map<String, Object?> params;
  final Cause cause;

  Principal get by => cause.by;

  /// Completes when the deadline passes: the caller was answered
  /// `timedOut`. What the handler does after still stands (and its end is
  /// recorded as late), so a handler that can stop stops here.
  final Future<void> expired;

  /// The cause of what the handler does on behalf of [by]: nested calls
  /// and writes. Its parent is this call; the chain and the test mark
  /// carry over.
  Cause causeFor(Principal by) => cause.child(id, by: by);
}

/// A call on its way, as guards and before hooks see it.
final class PendingCall {
  const PendingCall._(
    this.id,
    this.command,
    this.params,
    this.cause, {
    required this.layerDispatch,
  });

  final String id;
  final CommandDescriptor command;
  final Map<String, Object?> params;
  final Cause cause;

  /// The registry made it to apply a layer.
  final bool layerDispatch;

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

/// The only write handle of a state.
final class RawStateWriter implements Handle {
  RawStateWriter._(this._r, this.descriptor, this.by);

  final Registry _r;
  final StateDescriptor descriptor;

  /// Who writes, for the causes of its writes.
  final Principal by;
  bool _disposed = false;

  /// Sets the value (of [key], for a keyed state).
  ///
  /// A write a handler makes passes [cause] (`call.causeFor(by)`), so it
  /// follows from the call; without it, the write starts a new chain.
  void set(Object? value, {String? key, Cause? cause}) {
    _live();
    _r._writeState(descriptor, key, value, cause ?? Cause(by));
  }

  /// Removes the value (of [key]).
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
final class RawFactEmitter implements Handle {
  RawFactEmitter._(
    this._r,
    this.descriptor,
    this.by,
    this._emitter, {
    required this.definer,
  });

  final Registry _r;
  final SignalEmitter<Object?> _emitter;
  final FactDescriptor descriptor;

  /// The producer, for the causes of its facts.
  final Principal by;

  /// Disposing this handle removes the fact from the catalog.
  final bool definer;
  bool _disposed = false;

  /// Emits [payload]. A fact whose [id] was seen within the dedup window is
  /// dropped; returns whether it was taken.
  bool emit(Object? payload, {String? id, Cause? cause}) {
    if (_disposed) throw StateError('${descriptor.name} is gone');
    return _r._emit(
      descriptor,
      _emitter,
      payload,
      id ?? newId(),
      cause ?? Cause(by),
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

final class _Disposer implements Handle {
  _Disposer(this._f);
  void Function()? _f;

  @override
  void dispose() {
    final f = _f;
    _f = null;
    f?.call();
  }
}

/// A layer a participant holds (SPEC §8).
final class LayerHandle implements Handle {
  LayerHandle._(this._r, this.id, this.state, this.key);

  final Registry _r;
  final String id;
  final String state;
  final String? key;

  /// Whether the layer is still there.
  bool get active => _r._layerById.containsKey(id);

  @override
  void dispose() => _r._dropLayer(id, LayerOutcome.removed);
}

typedef _Target = (String state, String? key);

final class _StateEntry {
  _StateEntry(this.descriptor, this.cell) : writer = cell.claim();
  final StateDescriptor descriptor;

  /// Its values by key, null for an unkeyed state; the registry is the
  /// cell's only writer.
  final KeyedCell<String?, Object?> cell;
  final KeyedCellWriter<String?, Object?> writer;
  String? setter;
}

final class _CommandEntry {
  _CommandEntry(this.descriptor, this.port, this.serving, this.available);
  final CommandDescriptor descriptor;
  final Port<CommandCall, Object?> port;
  final Handle serving;
  final Availability? available;
}

final class _FactEntry {
  _FactEntry(this.descriptor, this.signal);
  final FactDescriptor descriptor;

  /// Its payloads, tagged with their id and cause.
  final Signal<Object?> signal;
}

final class _Guard {
  _Guard(this.id, this.check, this.overridable);
  final String id;
  final GuardCheck check;
  final bool overridable;
}

final class _Hook {
  _Hook(this.id, this.run, this.priority, this.timeout, this.order);
  final String id;
  final BeforeHook run;
  final int priority;
  final Duration timeout;
  final int order;
}

/// A call waiting in its before stage, which a hurry may join (SPEC §11).
final class _Waiting {
  _Waiting(this.params, this.hooks);
  final Map<String, Object?> params;

  /// The ids of the hooks it may run, so their own calls do not join it.
  final List<String> hooks;
  final Completer<void> hurry = Completer();
  final Completer<CallResult<Object?>> result = Completer();
}

final class _Layer {
  _Layer({
    required this.id,
    required this.target,
    required this.owner,
    required this.by,
    required this.value,
    required this.priority,
    required this.order,
    required this.chain,
    this.expiresAt,
    this.claimed = true,
  });

  final String id;
  final _Target target;
  final String owner;
  final Principal by;
  final Object? value;
  final int priority;
  final int order;
  final List<String> chain;
  final DateTime? expiresAt;
  bool claimed;
  Timer? timer;
}

final class _Stack {
  final List<_Layer> layers = [];
  bool hasBase = false;
  Object? base;

  /// Calls dispatching a layer's value now; writes they cause are echoes.
  final Set<String> inflight = {};

  _Layer? get top {
    _Layer? best;
    for (final l in layers) {
      if (best == null ||
          l.priority > best.priority ||
          (l.priority == best.priority && l.order > best.order)) {
        best = l;
      }
    }
    return best;
  }
}

/// The registry: the vocabulary, its values, calls, guards, before hooks,
/// layers and the feed (SPEC §§5–12).
///
/// One isolate, one writer: every commit happens here in order, so seq is a
/// total order. Participants hold handles and never each other.
final class Registry implements TypeContext {
  Registry({
    this.dedupWindow = const Duration(minutes: 10),
    this.retainTicks = 1000,
    this.recentPerFact = 100,
    this.claimGrace = const Duration(seconds: 30),
    Set<String> overriders = const {},
    Clock? clock,
    ErrorSink? onError,
  }) : clock = clock ?? clock_zone.clock,
       overriders = Set.unmodifiable(overriders),
       _onError = onError ?? Zone.current.handleUncaughtError,
       epoch = newId() {
    _hub = Hub(onCommit: _committed);
  }

  /// Commits every state value and fact of the registry (SPEC §7, §21).
  late final Hub _hub;

  /// How long ids of calls and facts are remembered to drop repeats.
  final Duration dedupWindow;

  /// How many ticks a feed can resume from.
  final int retainTicks;

  /// How many facts of each name [recent] keeps.
  final int recentPerFact;

  /// How long imported layers wait to be claimed (SPEC §8).
  final Duration claimGrace;

  /// The principal kinds that may override a guard's overridable denial and
  /// hurry an interceptable call.
  final Set<String> overriders;

  /// This registry's run; seq counts within it.
  final String epoch;

  /// Where the registry and its clients read the time; the zone's clock
  /// when the registry was made, unless given.
  final Clock clock;

  final ErrorSink _onError;

  /// The seq of the last commit.
  int get seq => _hub.seq;

  // --- Catalog ---------------------------------------------------------------

  final Map<String, EntityKind> _kinds = {};
  final Map<String, String? Function(Object?)> _customTypes = {};
  final Map<String, _StateEntry> _states = {};
  final Map<String, _CommandEntry> _commands = {};
  final Map<String, _FactEntry> _facts = {};

  /// The state or fact each cell and signal holds.
  final Map<Object, String> _names = Map.identity();
  final StreamController<CatalogChange> _catalog = StreamController.broadcast();

  void _announce(CatalogChange c) {
    if (!_catalog.isClosed) _catalog.add(c);
  }

  /// Additions, removals and entity changes, in order.
  Stream<CatalogChange> get catalogChanges => _catalog.stream;

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
      _commands[canonical(name)]?.descriptor;

  FactDescriptor? factDescriptor(String name) =>
      _facts[canonical(name)]?.descriptor;

  /// Why [command] cannot run now (it is not there, or its owner says it
  /// is unavailable), or null when it can. Guards are not asked: they judge
  /// a call, not a command.
  String? whyUnavailable(String command) {
    final c = _commands[canonical(command)];
    if (c == null) return 'no command $command';
    return c.available?.call();
  }

  /// The command that sets [state], if there is one.
  String? setterOf(String state) => _states[canonical(state)]?.setter;

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

  /// Whether [by] may read state [name]'s values, or hear fact [name], over
  /// remote and the MCP board (its `readers`); true for a word there is
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
    'unavailable': {
      for (final name in _commands.keys) name: ?whyUnavailable(name),
    },
  };

  List<String> _unreadable(Principal by) => [
    for (final s in _states.values)
      if (!(s.descriptor.readers?.allows(by) ?? true)) s.descriptor.name,
    for (final f in _facts.values)
      if (!(f.descriptor.readers?.allows(by) ?? true)) f.descriptor.name,
  ];

  /// Registers an entity kind (SPEC §3); withdraw it with the handle.
  Handle registerKind(EntityKind kind) {
    if (_kinds.containsKey(kind.name)) {
      throw StateError('kind ${kind.name} exists');
    }
    _kinds[kind.name] = kind;
    _announce(KindChanged(kind.name));
    return _Disposer(() {
      if (_kinds[kind.name] == kind) {
        _kinds.remove(kind.name);
        _announce(KindChanged(kind.name));
      }
    });
  }

  /// The entities of [kind] changed.
  void entitiesChanged(String kind) => _announce(KindChanged(kind));

  /// Registers the host's type [name] with its checker (SPEC §2).
  Handle registerType(String name, String? Function(Object? value) check) {
    checkName(name, 'type');
    if (_customTypes.containsKey(name)) throw StateError('type $name exists');
    _customTypes[name] = check;
    return _Disposer(() => _customTypes.remove(name));
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
  /// renamed goes on answering to its old name, in calls, reads, facts and
  /// links, so what names it (the user's links, a plugin) keeps working.
  /// `describe` lists it under `aliases`. Dispose the handle to drop it.
  Handle alias(String old, String now) {
    checkName(old, 'old');
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
    return _Disposer(() {
      if (_aliases.remove(old) != null) _announce(AliasChanged(old));
    });
  }

  /// Defines a state; the returned writer is its only write handle.
  RawStateWriter defineState(StateDescriptor d, {required Principal by}) {
    _checkFree(d.name);
    final cell = KeyedCell<String?, Object?>(hub: _hub, equals: jsonEquals);
    final e = _StateEntry(d, cell);
    _names[cell] = d.name;
    for (final c in _commands.values) {
      if (c.descriptor.sets?.state == d.name) e.setter = c.descriptor.name;
    }
    _states[d.name] = e;
    _announce(DescriptorAdded(d));
    return RawStateWriter._(this, d, by);
  }

  /// Defines a command served by [handler]; dispose the handle to remove it.
  Handle defineCommand(
    CommandDescriptor d,
    CommandHandler handler, {
    Availability? available,
  }) {
    _checkFree(d.name);
    if (d.sets case final s?) {
      final st = _states[s.state];
      if (st != null && st.setter != null) {
        throw StateError('${s.state} already has a setter, ${st.setter}');
      }
      for (final c in _commands.values) {
        if (c.descriptor.sets?.state == s.state) {
          throw StateError('${s.state} already has a setter');
        }
      }
      st?.setter = d.name;
    }
    final port = Port<CommandCall, Object?>();
    _commands[d.name] = _CommandEntry(d, port, port.serve(handler), available);
    _announce(DescriptorAdded(d));
    return _Disposer(() => _undefine(d.name));
  }

  /// Defines a fact; the returned emitter belongs to the definer.
  RawFactEmitter defineFact(FactDescriptor d, {required Principal by}) {
    _checkFree(d.name);
    final signal = Signal<Object?>(hub: _hub, open: d.open);
    _facts[d.name] = _FactEntry(d, signal);
    _names[signal] = d.name;
    _announce(DescriptorAdded(d));
    return RawFactEmitter._(this, d, by, signal.claim(), definer: true);
  }

  /// Another emit handle of an open fact, for producer [by]. The host
  /// decides who gets one.
  RawFactEmitter producer(String fact, {required Principal by}) {
    final f = _facts[canonical(fact)];
    if (f == null) throw StateError('no fact $fact');
    final d = f.descriptor;
    if (!d.open) throw StateError('$fact is not open');
    return RawFactEmitter._(this, d, by, f.signal.claim(), definer: false);
  }

  void _undefine(String name) {
    if (_states[name] case final s?) {
      // The values go in one tick, while the entry is still there to
      // commit against.
      batch(() {
        for (final key in [...s.cell.values.keys]) {
          s.writer.remove(key, tag: Cause(Principal.system));
        }
      });
      _states.remove(name);
      // Inside an outer batch, its removes go with the state, uncommitted.
      s.cell.close();
      _names.remove(s.cell);
      for (final t in [..._stacks.keys]) {
        if (t.$1 == name) _orphan(t);
      }
      _announce(DescriptorRemoved(s.descriptor));
    } else if (_commands.remove(name) case final c?) {
      c.serving.dispose();
      if (c.descriptor.sets case final s?) {
        _states[s.state]?.setter = null;
        for (final t in [..._stacks.keys]) {
          if (t.$1 == s.state) _orphan(t);
        }
      }
      for (final w in _waiting[name] ?? const <_Waiting>[]) {
        if (!w.result.isCompleted) {
          w.result.complete(
            CallRefused(Refusal.unknownCommand, '$name is gone'),
          );
        }
        if (!w.hurry.isCompleted) w.hurry.complete();
      }
      _waiting.remove(name);
      _hooks.remove(name);
      _announce(DescriptorRemoved(c.descriptor));
    } else if (_facts.remove(name) case final f?) {
      f.signal.close();
      _names.remove(f.signal);
      _announce(DescriptorRemoved(f.descriptor));
    }
  }

  // --- Ticks -----------------------------------------------------------------

  final StreamController<Tick> _ticks = StreamController.broadcast();
  final ListQueue<Tick> _retained = ListQueue();
  final Map<String, ListQueue<FactMessage>> _recent = {};

  /// Every commit, in seq order, delivered asynchronously.
  Stream<Tick> get ticks => _ticks.stream;

  /// Runs [body] synchronously and commits everything it wrote as one tick
  /// (SPEC §7). Batches nest; the outermost commits.
  void batch(void Function() body) => _hub.batch(body);

  void _writeState(StateDescriptor d, String? key, Object? value, Cause cause) {
    final e = _liveState(d);
    _checkKey(d, key);
    final v = freezeJson(d.type.check(value, this));
    e.writer.set(key, v, tag: cause);
  }

  void _removeState(StateDescriptor d, String? key, Cause cause) {
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

  /// Turns what the hub committed into the registry's tick: names, ids,
  /// causes and the time.
  void _committed(HubTick t) {
    final now = clock.now();
    final changes = <StateChange>[
      for (final c in t.changes)
        StateChange(
          seq: c.seq,
          id: newId(),
          state: _names[c.store]!,
          key: c.key as String?,
          value: c.value,
          previous: c.previous,
          removed: c.removed,
          cause: c.tag! as Cause,
          at: now,
        ),
    ];
    final committed = <FactMessage>[
      for (final e in t.emits)
        if (e.tag case (final String id, final Cause cause))
          FactMessage(
            seq: e.seq,
            id: id,
            fact: _names[e.signal]!,
            payload: e.value,
            cause: cause,
            at: now,
          ),
    ];
    final tick = Tick(
      epoch: epoch,
      from: t.from,
      to: t.to,
      changes: List.unmodifiable(changes),
      facts: List.unmodifiable(committed),
    );
    _retained.add(tick);
    while (_retained.length > retainTicks) {
      _retained.removeFirst();
      _forgotTicks = true;
    }
    for (final f in committed) {
      final q = _recent.putIfAbsent(f.fact, ListQueue.new);
      q.add(f);
      while (q.length > recentPerFact) {
        q.removeFirst();
      }
    }
    if (!_ticks.isClosed) _ticks.add(tick);
    for (final c in changes) {
      _checkOverride(c);
    }
  }

  // --- Reading ---------------------------------------------------------------

  /// The value of [state] (of [key]); inside a batch, the batch's own
  /// writes count (SPEC §7). Null when there is none.
  Object? read(String state, {String? key}) {
    return _states[canonical(state)]?.cell.read(key);
  }

  /// Whether [state] (of [key]) has a committed value.
  bool has(String state, {String? key}) =>
      _states[canonical(state)]?.cell.has(key) ?? false;

  /// Every committed value of [state], by key (null for an unkeyed one).
  Map<String?, Object?> readAll(String state) =>
      _states[canonical(state)]?.cell.values ?? const {};

  /// The value of [state] (of [key]) now, then on every change; null when
  /// there is none.
  Stream<Object?> watch(String state, {String? key}) {
    state = canonical(state);
    late StreamController<Object?> out;
    StreamSubscription<Tick>? sub;
    out = StreamController<Object?>(
      onListen: () {
        out.add(read(state, key: key));
        sub = ticks.listen((t) {
          for (final c in t.changes) {
            if (c.state == state && c.key == key) out.add(c.value);
          }
        });
      },
      onCancel: () => sub?.cancel(),
    );
    return out.stream;
  }

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
    if (q == null) return const [];
    final all = q.toList();
    return n == null || n >= all.length ? all : all.sublist(all.length - n);
  }

  /// The fact of id [id] among those kept, or null: what follows from it
  /// (a remote participant's answer to it) takes its cause.
  FactMessage? recentFact(String id) {
    for (final q in _recent.values) {
      for (final m in q) {
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
              states: {
                for (final e in _states.entries) e.key: e.value.cell.values,
              },
              factsLost: since != null,
            ),
          );
        }
        sub = ticks.listen((t) {
          if (t.to <= last) return;
          last = t.to;
          out.add(t);
        });
      },
      onCancel: () => sub?.cancel(),
    );
    return out.stream;
  }

  // --- Facts -----------------------------------------------------------------

  final LinkedHashMap<String, DateTime> _seenFacts = LinkedHashMap();

  bool _emit(
    FactDescriptor d,
    SignalEmitter<Object?> emitter,
    Object? payload,
    String id,
    Cause cause,
  ) {
    if (_facts[d.name]?.descriptor != d) throw StateError('${d.name} is gone');
    final now = clock.now();
    _forget(_seenFacts, (at) => at, now);
    if (_seenFacts.containsKey(id)) return false;
    final v = freezeJson(d.type.check(payload, this));
    _seenFacts[id] = now;
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

  // --- Calls -----------------------------------------------------------------

  final LinkedHashMap<String, _Seen> _calls = LinkedHashMap();
  final Map<String, _Guard> _guards = {};
  final Map<String, List<_Hook>> _hooks = {};
  final Map<String, List<_Waiting>> _waiting = {};
  int _hookOrder = 0;
  final StreamController<CallRecord> _records = StreamController.broadcast();

  /// Every finished call (SPEC §9).
  Stream<CallRecord> get calls => _records.stream;

  final LinkedHashMap<String, CallRecord> _recentCalls = LinkedHashMap();

  // Whether retention dropped ticks or call records: what explain cannot
  // find may be forgotten rather than never there.
  bool _forgotTicks = false;
  bool _forgotCalls = false;

  void _remember(CallRecord record) {
    _recentCalls[record.id] = record;
    while (_recentCalls.length > retainTicks) {
      _recentCalls.remove(_recentCalls.keys.first);
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
      layers: [
        for (final l in layers())
          if (l.state == state && l.key == key) l,
      ],
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

  /// Calls [command] on behalf of [by] (SPEC §9). A repeated [id] within
  /// the dedup window answers the first call's result without running it
  /// again. A call made by a handler or a hook passes [cause]; without it,
  /// the call starts a new chain.
  Future<CallResult<Object?>> call(
    String command,
    Map<String, Object?> params, {
    required Principal by,
    String? id,
    bool override = false,
    Cause? cause,
  }) {
    command = canonical(command);
    final callId = id ?? newId();
    final now = clock.now();
    _forget(_calls, (c) => c.at, now);
    if (_calls[callId] case final seen?) {
      // An id stands for one call: another one with it is refused, not
      // answered the first call's result.
      if (seen.command != command ||
          seen.by != by ||
          !jsonEquals(seen.params, params)) {
        return Future.value(
          CallRefused(
            Refusal.idConflict,
            'id $callId was given to another call',
          ),
        );
      }
      return seen.result;
    }
    final result = _run(
      callId,
      command,
      params,
      cause ?? Cause(by),
      override: override,
      layer: null,
    );
    _calls[callId] = _Seen(now, command, freezeJson(params), by, result);
    return result;
  }

  Future<CallResult<Object?>> _run(
    String id,
    String command,
    Map<String, Object?> rawParams,
    Cause cause, {
    required bool override,
    required _Target? layer,
  }) async {
    final started = clock.now();
    final overridden = <String>[];
    final hooksRan = <String>[];
    var params = rawParams;

    CallResult<Object?> finish(CallResult<Object?> r, {bool late = false}) {
      if (!_records.isClosed) {
        _remember(
          CallRecord(
            id: id,
            command: command,
            params: params,
            cause: cause,
            result: r,
            overridden: overridden,
            hooks: hooksRan,
            layerDispatch: layer != null,
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
      params =
          freezeJson(d.params.check(rawParams, this)) as Map<String, Object?>;
    } on TypeMismatch catch (e) {
      return finish(CallRefused(Refusal.invalidParams, '$e'));
    }
    if (!d.callers.allows(cause.by)) {
      return finish(
        CallRefused(Refusal.notPermitted, '${cause.by} may not call $command'),
      );
    }
    if (overriders.contains(cause.by.kind)) {
      for (final w in _waiting[command] ?? const <_Waiting>[]) {
        if (jsonEquals(w.params, params) && !w.hooks.any(cause.came)) {
          if (!w.hurry.isCompleted) w.hurry.complete();
          return w.result.future;
        }
      }
    }
    if (entry.available?.call() case final why?) {
      return finish(CallRefused(Refusal.unavailable, why));
    }
    final pending = PendingCall._(
      id,
      d,
      params,
      cause,
      layerDispatch: layer != null,
    );
    for (final g in [..._guards.values]) {
      String? why;
      try {
        why = g.check(pending);
      } catch (e, s) {
        _onError(e, s);
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

    final hooks = d.interceptable ? [...?_hooks[command]] : const <_Hook>[];
    _Waiting? waiting;
    if (hooks.isNotEmpty) {
      hooks.sort(
        (a, b) => a.priority != b.priority
            ? b.priority.compareTo(a.priority)
            : a.order.compareTo(b.order),
      );
      waiting = _Waiting(params, [for (final h in hooks) h.id]);
      (_waiting[command] ??= []).add(waiting);
      for (final h in hooks) {
        if (waiting.hurry.isCompleted || waiting.result.isCompleted) break;
        if (cause.came(h.id)) continue;
        if (_hooks[command]?.contains(h) != true) continue;
        hooksRan.add(h.id);
        final hookCause = Cause(
          cause.by,
          parent: id,
          chain: [...cause.chain, h.id],
          test: cause.test,
        );
        try {
          await Future.any([
            h.run(pending, hookCause).timeout(h.timeout),
            waiting.hurry.future,
          ]);
        } catch (e, s) {
          if (e is! TimeoutException) _onError(e, s);
        }
      }
      _waiting[command]?.remove(waiting);
      if (waiting.result.isCompleted) {
        return finish(await waiting.result.future);
      }
    }

    final current = _commands[command];
    if (current != entry) {
      final r = CallRefused(Refusal.unknownCommand, '$command is gone');
      waiting?.result.complete(r);
      return finish(r);
    }

    CallResult<Object?> answered(Object? answer) {
      if (d.returns case final t?) {
        try {
          return CallDone(freezeJson(t.check(answer, this)));
        } on TypeMismatch catch (e) {
          return CallFailed('returned a wrong value: $e');
        }
      }
      return const CallDone(null);
    }

    void explicit(CallResult<Object?> r) {
      if (!r.ok || layer != null) return;
      if (d.sets case final s?) {
        final key = s.key == null ? null : params[s.key] as String?;
        _explicitSet((s.state, key), params[s.value]);
      }
    }

    if (layer != null) _stacks[layer]?.inflight.add(id);
    final expired = Completer<void>();
    final work = Future.sync(
      () => entry.port.call(
        CommandCall._(id, command, params, cause, expired.future),
      ),
    );
    CallResult<Object?> result;
    try {
      result = answered(await work.timeout(d.deadline));
    } on TimeoutException {
      result = const CallTimedOut();
      expired.complete();
      // The handler goes on: its end is recorded as late, and a retry with
      // the call's id answers it.
      unawaited(
        work.then(answered, onError: (Object e) => CallFailed(e)).then((r) {
          explicit(r);
          if (_calls[id] case final c?) {
            c.result = Future.value(r);
          }
          finish(r, late: true);
        }),
      );
    } catch (e) {
      result = CallFailed(e);
    } finally {
      if (layer != null) _stacks[layer]?.inflight.remove(id);
    }
    explicit(result);
    waiting?.result.complete(result);
    return finish(result);
  }

  /// Adds a guard (SPEC §10), asked for every call in the order guards
  /// were added.
  Handle addGuard(String id, GuardCheck check, {bool overridable = true}) {
    if (_guards.containsKey(id)) throw StateError('guard $id exists');
    final g = _Guard(id, check, overridable);
    _guards[id] = g;
    return _Disposer(() {
      if (_guards[id] == g) _guards.remove(id);
    });
  }

  /// Adds a before hook to the interceptable [command] (SPEC §11).
  Handle addBefore(
    String command,
    String id,
    BeforeHook run, {
    int priority = 0,
    required Duration timeout,
  }) {
    final c = _commands[command];
    if (c == null) throw StateError('no command $command');
    if (!c.descriptor.interceptable) {
      throw StateError('$command is not interceptable');
    }
    final list = _hooks.putIfAbsent(command, () => []);
    if (list.any((h) => h.id == id)) throw StateError('hook $id exists');
    final h = _Hook(id, run, priority, timeout, _hookOrder++);
    list.add(h);
    return _Disposer(() => _hooks[command]?.remove(h));
  }

  // --- Layers ----------------------------------------------------------------

  final Map<_Target, _Stack> _stacks = {};
  final Map<String, _Layer> _layerById = {};
  final StreamController<LayerEvent> _layerEvents =
      StreamController.broadcast();
  int _layerOrder = 0;
  Timer? _graceTimer;

  /// What happened to layers: dropped, refused (SPEC §8).
  Stream<LayerEvent> get layerEvents => _layerEvents.stream;

  /// The value [state] (of [key]) is held at by layers, or its base;
  /// `(has: false)` when neither is known.
  ({bool has, Object? value}) effective(String state, {String? key}) {
    final s = _stacks[(state, key)];
    if (s == null || s.layers.isEmpty) {
      return (has: has(state, key: key), value: read(state, key: key));
    }
    return (has: true, value: s.top!.value);
  }

  /// Holds [state] (of [key]) at [value] for [owner] (SPEC §8).
  LayerHandle pushLayer(
    String state, {
    String? key,
    required Object? value,
    required String owner,
    required Principal by,
    int priority = 0,
    Duration? ttl,
    List<String> chain = const [],
  }) {
    state = canonical(state);
    final e = _states[state];
    if (e == null) throw StateError('no state $state');
    if (e.setter == null) throw StateError('$state has no setter');
    _checkKey(e.descriptor, key);
    final v = freezeJson(e.descriptor.type.check(value, this));
    final layer = _Layer(
      id: newId(),
      target: (state, key),
      owner: owner,
      by: by,
      value: v,
      priority: priority,
      order: _layerOrder++,
      chain: chain,
      expiresAt: ttl == null ? null : clock.now().add(ttl),
    );
    _addLayer(layer);
    _resolve(layer.target);
    return LayerHandle._(this, layer.id, state, key);
  }

  void _addLayer(_Layer layer, {Object? base, bool? hasBase}) {
    final stack = _stacks.putIfAbsent(layer.target, _Stack.new);
    if (stack.layers.isEmpty && !stack.hasBase) {
      if (hasBase ?? has(layer.target.$1, key: layer.target.$2)) {
        stack.hasBase = true;
        stack.base = hasBase == null
            ? read(layer.target.$1, key: layer.target.$2)
            : base;
      }
    }
    stack.layers.add(layer);
    _layerById[layer.id] = layer;
    if (layer.expiresAt case final at?) {
      final left = at.difference(clock.now());
      layer.timer = Timer(
        left.isNegative ? Duration.zero : left,
        () => _dropLayer(layer.id, LayerOutcome.expired),
      );
    }
  }

  void _dropLayer(String id, LayerOutcome outcome, {String? reason}) {
    final layer = _layerById.remove(id);
    if (layer == null) return;
    layer.timer?.cancel();
    final stack = _stacks[layer.target];
    stack?.layers.remove(layer);
    _event(layer, outcome, reason);
    _resolve(layer.target);
  }

  void _event(_Layer l, LayerOutcome outcome, String? reason) {
    if (_layerEvents.isClosed) return;
    _layerEvents.add(
      LayerEvent(
        layer: l.id,
        owner: l.owner,
        state: l.target.$1,
        key: l.target.$2,
        outcome: outcome,
        reason: reason,
      ),
    );
  }

  /// Dispatches the effective value of [t] when it differs from the value
  /// there is.
  void _resolve(_Target t) {
    final stack = _stacks[t];
    if (stack == null) return;
    final setter = _states[t.$1]?.setter;
    if (stack.layers.isEmpty) {
      _stacks.remove(t);
      if (setter != null &&
          stack.hasBase &&
          !jsonEquals(read(t.$1, key: t.$2), stack.base)) {
        _dispatch(t, setter, stack.base, Principal.system, const [], null);
      }
      return;
    }
    if (setter == null) return;
    final top = stack.top!;
    if (has(t.$1, key: t.$2) && jsonEquals(read(t.$1, key: t.$2), top.value)) {
      return;
    }
    _dispatch(t, setter, top.value, top.by, [...top.chain, top.owner], top);
  }

  void _dispatch(
    _Target t,
    String setter,
    Object? value,
    Principal by,
    List<String> chain,
    _Layer? layer,
  ) {
    final sets = _commands[setter]?.descriptor.sets;
    if (sets == null) return;
    final params = <String, Object?>{sets.value: value, ?sets.key: t.$2};
    _run(
      newId(),
      setter,
      params,
      Cause(by, chain: chain),
      override: false,
      layer: t,
    ).then((r) {
      if (r is CallRefused && layer != null && _layerById[layer.id] != null) {
        _event(layer, LayerOutcome.refused, r.reason);
      }
    });
  }

  /// An explicit set of [t] succeeded: [value] is the new base, layers go.
  void _explicitSet(_Target t, Object? value) {
    final stack = _stacks[t];
    if (stack == null || stack.layers.isEmpty) return;
    _stacks.remove(t);
    for (final l in [...stack.layers]) {
      _layerById.remove(l.id);
      l.timer?.cancel();
      _event(l, LayerOutcome.overridden, null);
    }
  }

  /// A committed change that is not an echo of a dispatch and differs from
  /// the layers' value clears them (SPEC §8).
  void _checkOverride(StateChange c) {
    final t = (c.state, c.key);
    final stack = _stacks[t];
    if (stack == null || stack.layers.isEmpty) return;
    if (c.cause.parent != null && stack.inflight.contains(c.cause.parent)) {
      return;
    }
    if (!c.removed && jsonEquals(c.value, stack.top!.value)) return;
    _explicitSet(t, c.value);
  }

  void _orphan(_Target t) {
    final stack = _stacks.remove(t);
    if (stack == null) return;
    for (final l in stack.layers) {
      _layerById.remove(l.id);
      l.timer?.cancel();
      _event(l, LayerOutcome.orphaned, null);
    }
  }

  /// The layers there are, to restore after a restart (SPEC §8).
  Map<String, Object?> exportLayers() => {
    'version': 1,
    'stacks': [
      for (final MapEntry(key: t, value: s) in _stacks.entries)
        if (s.layers.isNotEmpty)
          {
            'state': t.$1,
            'key': ?t.$2,
            if (s.hasBase) 'base': s.base,
            'hasBase': s.hasBase,
            'layers': [
              for (final l in s.layers)
                {
                  'id': l.id,
                  'owner': l.owner,
                  'by': l.by.toJson(),
                  'value': l.value,
                  'priority': l.priority,
                  'order': l.order,
                  if (l.chain.isNotEmpty) 'chain': l.chain,
                  if (l.expiresAt case final at?)
                    'expiresAt': at.toUtc().millisecondsSinceEpoch,
                },
            ],
          },
    ],
  };

  /// Restores exported layers, unclaimed: owners [claim] them within
  /// [claimGrace], or they go (SPEC §8). Expired ones are dropped now.
  void importLayers(Map<String, Object?> json) {
    final version = json['version'] as int? ?? 0;
    if (version > 1) throw FormatException('layers of version $version');
    final now = clock.now();
    final touched = <_Target>{};
    for (final s in json['stacks'] as List? ?? const []) {
      final m = s as Map;
      final t = (m['state'] as String, m['key'] as String?);
      final e = _states[t.$1];
      if (e == null || e.setter == null) continue;
      for (final raw in m['layers'] as List) {
        final l = raw as Map;
        final exp = l['expiresAt'] as int?;
        final expiresAt = exp == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(exp, isUtc: true);
        if (expiresAt != null && !expiresAt.isAfter(now)) continue;
        Object? value;
        try {
          value = freezeJson(e.descriptor.type.check(l['value'], this));
        } on TypeMismatch {
          continue;
        }
        final order = l['order'] as int? ?? 0;
        if (order >= _layerOrder) _layerOrder = order + 1;
        _addLayer(
          _Layer(
            id: l['id'] as String,
            target: t,
            owner: l['owner'] as String,
            by: Principal.fromJson(l['by']),
            value: value,
            priority: l['priority'] as int? ?? 0,
            order: order,
            chain: [
              for (final c in l['chain'] as List? ?? const []) c as String,
            ],
            expiresAt: expiresAt,
            claimed: false,
          ),
          base: m['base'],
          // Without a saved base, the value there is now is the base.
          hasBase: m['hasBase'] == true ? true : null,
        );
        touched.add(t);
      }
    }
    for (final t in touched) {
      _resolve(t);
    }
    _graceTimer?.cancel();
    _graceTimer = Timer(claimGrace, () {
      for (final l in [..._layerById.values]) {
        if (!l.claimed) _dropLayer(l.id, LayerOutcome.unclaimed);
      }
    });
  }

  /// Claims the imported layers of [owner]; answers their handles.
  List<LayerHandle> claim(String owner) => [
    for (final l in _layerById.values)
      if (l.owner == owner && !l.claimed)
        LayerHandle._(this, (l..claimed = true).id, l.target.$1, l.target.$2),
  ];

  /// Every layer there is now: what holds which state at which value.
  List<LayerInfo> layers() => [
    for (final MapEntry(key: t, value: s) in _stacks.entries)
      for (final l in s.layers)
        LayerInfo(
          id: l.id,
          state: t.$1,
          key: t.$2,
          value: l.value,
          owner: l.owner,
          by: l.by,
          priority: l.priority,
          top: identical(s.top, l),
          expiresAt: l.expiresAt,
          claimed: l.claimed,
        ),
  ];

  /// The layers [owner] holds now.
  List<LayerHandle> layersOf(String owner) => [
    for (final l in _layerById.values)
      if (l.owner == owner) LayerHandle._(this, l.id, l.target.$1, l.target.$2),
  ];

  /// Drops every layer of [owner].
  void dropLayersOf(String owner) {
    for (final l in [..._layerById.values]) {
      if (l.owner == owner) _dropLayer(l.id, LayerOutcome.removed);
    }
  }

  // --- Lifetime --------------------------------------------------------------

  /// Closes the streams and stops the timers.
  Future<void> dispose() async {
    _graceTimer?.cancel();
    for (final l in _layerById.values) {
      l.timer?.cancel();
    }
    await Future.wait([
      _ticks.close(),
      _hub.dispose(),
      _catalog.close(),
      _records.close(),
      _layerEvents.close(),
    ]);
  }
}

/// A call id seen within the dedup window, and the call it was given for.
final class _Seen {
  _Seen(this.at, this.command, this.params, this.by, this.result);
  final DateTime at;
  final String command;
  final Object? params;
  final Principal by;
  Future<CallResult<Object?>> result;
}
