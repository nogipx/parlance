import 'dart:async';
import 'dart:collection';

import '../link_words.dart';
import '../registry/cause.dart';
import '../registry/descriptors.dart';
import '../registry/ids.dart';
import '../registry/json.dart';
import '../registry/messages.dart';
import '../registry/registry.dart';
import '../registry/types.dart';
import '../registry/words.dart';
import 'controls.dart';
import 'expr.dart';
import 'model.dart';

/// What an extension makes of data its base trigger fired with: possibly
/// other data and the principal the run acts for.
typedef ExtensionHit = ({Object? data, Principal? by});

/// A trigger of the host's (SPEC §13.2): it stands for one of the
/// package's triggers and may filter and reshape what that one fires with.
final class TriggerExtension {
  const TriggerExtension(this.name, {required this.translate, this.accept});

  /// The key that names it in a definition.
  final String name;

  /// The trigger it stands for, from every key of the definition but
  /// `throttle` and `once`. Throws [FormatException] for bad options.
  final Trigger Function(Map<String, Object?> options) translate;

  /// Whether a firing of the base trigger is this extension's, and with
  /// what data and principal; null — not this one. Without it, every
  /// firing is, unchanged.
  final ExtensionHit? Function(Object? data, Map<String, Object?> options)?
  accept;
}

/// A home for bindings (SPEC §13.6): an entity kind and the condition an
/// entity of it makes.
final class AnchorKind {
  const AnchorKind(
    this.name, {
    required this.entityKind,
    required this.condition,
  });

  final String name;
  final String entityKind;
  final Condition Function(String entity) condition;
}

/// A link's state, with what it lacks or why.
final class LinkStatus {
  const LinkStatus(this.id, this.state, {this.missing = const [], this.reason});

  final String id;
  final LinkState state;
  final List<String> missing;
  final String? reason;

  Map<String, Object?> toJson() => {
    'state': state.name,
    if (missing.isNotEmpty) 'missing': missing,
    'reason': ?reason,
  };

  @override
  String toString() =>
      'LinkStatus($id ${state.name}${missing.isEmpty ? '' : ' missing $missing'}'
      '${reason == null ? '' : ': $reason'})';
}

/// A definition that could not be taken.
final class LinkProblem {
  const LinkProblem(this.id, this.message);
  final String? id;
  final String message;

  @override
  String toString() => 'LinkProblem(${id ?? '?'}: $message)';
}

/// Where the user's own links are kept (SPEC §13): the host's file, a
/// project. The engine loads them once, saves them on every change made
/// through its commands, and loads them again on [Links.reloadOwn].
abstract interface class LinksStore {
  List<Map<String, Object?>> load();
  void save(List<Map<String, Object?>> links);
}

const _engine = Principal(LinkWords.kind);

/// The principal the engine acts as for the link [id].
Principal linkPrincipal(String id) => Principal(LinkWords.kind, id);

/// The links engine (SPEC §13): own words and the four relations, on the
/// public API of a [Registry] only.
final class Links {
  Links(
    this.registry, {
    this.rateLimit = 20,
    this.rateWindow = const Duration(minutes: 1),
    Callers? pressers,
    Callers? managers,
    Map<String, Object?> ownStates = const {},
    this.store,
    ErrorSink? onError,
  }) : _onError = onError ?? Zone.current.handleUncaughtError,
       _ownValues = {...ownStates} {
    final anyone = Callers(const {'*': Access.allow, 'system': Access.deny});
    _managers = managers ?? anyone;
    _handles.add(
      registry.registerKind(
        EntityKind(
          LinkWords.kind,
          list: () => [
            for (final id in {..._links.keys, ..._invalid.keys}) EntityRef(id),
          ],
        ),
      ),
    );
    _status = registry.state(LinkWords.status).define(by: _engine);
    _disabledFact = registry.fact(LinkWords.disabled).define(by: _engine);
    final manage = managers ?? anyone;
    _ownState = registry
        .state(LinkWords.own)
        .define(by: _engine, meta: const {'label': "The user's own links"});
    _handles.addAll([
      _status,
      _disabledFact,
      registry
          .command(LinkWords.press)
          .define(_press, callers: pressers ?? anyone),
      registry.command(LinkWords.tryOut).define(_try, callers: manage),
      registry.command(LinkWords.reset).define((c) {
        if (_live[c.params.link] case final _LiveReaction r) r.fired.clear();
      }, callers: manage),
      registry.command(LinkWords.stop).define((c) {
        if (_live[c.params.link] case final _LiveReaction r) r.stopAll();
      }, callers: manage),
      registry.command(LinkWords.enabledSet).define((c) {
        final EnableLink(link: id, :on) = c.params;
        if (on) {
          _disabled.remove(id);
        } else {
          _disabled[id] = 'turned off';
        }
        _reconcile();
      }, callers: manage),
      _ownState,
      registry
          .command(LinkWords.check)
          .define(
            (c) => check(c.params.link),
            callers: manage,
            meta: const {'label': 'Check a link without applying it'},
          ),
      registry
          .command(LinkWords.set)
          .define(
            (c) => _setOwn(c.params.links),
            callers: manage,
            meta: const {'label': "Replace the user's own links"},
          ),
      registry
          .command(LinkWords.upsert)
          .define(
            (c) {
              final link = c.params.link;
              final id = link is Map ? link['id'] : null;
              _setOwn([
                for (final l in _own)
                  if (l['id'] != id) l,
                link,
              ], keepOrderOf: id);
            },
            callers: manage,
            meta: const {'label': 'Add or replace one own link'},
          ),
      registry
          .command(LinkWords.remove)
          .define(
            (c) {
              final id = c.params.id;
              if (!_own.any((l) => l['id'] == id)) {
                throw StateError(
                  '$id is not an own link; turn a link of the host off with '
                  'an own link of the same id and enabled: false',
                );
              }
              _setOwn([
                for (final l in _own)
                  if (l['id'] != id) l,
              ]);
            },
            callers: manage,
            meta: const {'label': 'Remove one own link'},
          ),
    ]);
    _own = [...?store?.load()];
    _ownState.set(_own);
    for (final d in registry.catalog.whereType<StateDescriptor>()) {
      for (final e in registry.readAll(d.name).entries) {
        _view[(d.name, e.key)] = e.value;
      }
    }
    _subs.addAll([
      registry.ticks.listen(_onTick),
      registry.catalogChanges.listen((_) => _reconcile()),
      registry.layerEvents.listen(_onLayer),
    ]);
    if (_own.isNotEmpty) _compose();
  }

  final Registry registry;

  /// Where the user's own links are kept; null — in memory only.
  final LinksStore? store;

  /// The host's sets of links, by name, in the order they came: read-only
  /// to the user, who changes one by an own link of the same id.
  final Map<String, List<Map<String, Object?>>> _sources = {};
  List<Map<String, Object?>> _own = const [];
  late final StateWriterOf<List<Object?>> _ownState;

  /// What the last composition could not take.
  List<LinkProblem> problems = const [];

  /// The user's own links, as kept.
  List<Map<String, Object?>> get own => List.unmodifiable(_own);

  /// How many runs a link may have per [rateWindow] before it is disabled.
  final int rateLimit;
  final Duration rateWindow;

  final ErrorSink _onError;
  final Map<String, Object?> _ownValues;

  /// Who may manage links; who may use own words unless their definition
  /// says otherwise.
  late final Callers _managers;
  late final StateWriterOf<LinkStanding> _status;
  late final FactEmitterOf<LinkDisabled> _disabledFact;
  final List<Handle> _handles = [];
  final List<StreamSubscription<Object?>> _subs = [];

  final Map<String, Link> _links = {};
  final Map<String, String> _invalid = {};
  final Map<String, String> _disabled = {};
  final Map<String, String> _notes = {};
  final Map<String, _Live> _live = {};
  final Map<String, TriggerExtension> _extensions = {};
  final Map<String, AnchorKind> _anchors = {};
  final Map<String, LinkStatus> _statuses = {};
  final List<_Waiter> _waiters = [];

  /// The state as of the last tick handled: conditions of triggers and
  /// bindings read it, so they see the state at the position of the
  /// message they handle, not whatever was committed since (SPEC §7).
  final Map<(String, String?), Object?> _view = {};

  Object? _readView(String state, String? key) => _view[(state, key)];

  /// The definitions taken, by id.
  Map<String, Link> get links => Map.unmodifiable(_links);

  /// Where each link stands.
  Map<String, LinkStatus> get statuses => Map.unmodifiable(_statuses);

  /// The values of own states, to persist and give back to the next engine.
  Map<String, Object?> exportOwnStates() => Map.unmodifiable(_ownValues);

  /// Registers a trigger extension (SPEC §13.2).
  void registerTrigger(TriggerExtension ext) {
    if (_extensions.containsKey(ext.name)) {
      throw StateError('trigger ${ext.name} exists');
    }
    _extensions[ext.name] = ext;
    _reconcile();
  }

  /// Registers an anchor kind (SPEC §13.6).
  void registerAnchor(AnchorKind kind) {
    if (_anchors.containsKey(kind.name)) {
      throw StateError('anchor ${kind.name} exists');
    }
    _anchors[kind.name] = kind;
    _reconcile();
  }

  /// Sets the host's links named [name]: its own, an extension's. The
  /// user's own links come after every source; one with the id of a
  /// source's link replaces it. Answers what could not be taken.
  List<LinkProblem> source(String name, List<Object?> definitions) {
    _sources[name] = [
      for (final d in definitions)
        if (d is Map) d.cast<String, Object?>(),
    ];
    return _compose();
  }

  /// Loads the user's own links from [store] again, when the host changed
  /// them (an undo).
  List<LinkProblem> reloadOwn() {
    final next = [...?store?.load()];
    if (jsonEquals(next, _own)) return problems;
    _own = next;
    _ownState.set(_own);
    return _compose();
  }

  /// Takes [definitions] as the only source: the whole set of links but the
  /// user's own.
  List<LinkProblem> apply(List<Object?> definitions) =>
      source('main', definitions);

  /// The reactions someone can press now, in the order of the links: those
  /// active, with a manual trigger (or a host's that becomes one), whose
  /// `only` holds (SPEC §13.12).
  List<LinkControl> controls() => [
    for (final link in _links.values)
      if (_live[link.id] case final _LiveReaction live)
        if (live.triggers
                .map((t) => t.base)
                .whereType<ManualTrigger>()
                .firstOrNull
            case final manual?)
          if (live.link.only == null || evaluate(live.link.only!, registry))
            LinkControl(
              link: live.link,
              look: manual.look,
              lit: _lit(live.link, manual.look),
              unavailable: _unavailable(live.link),
            ),
  ];

  bool? _lit(Reaction link, Map<String, Object?> look) {
    if (look['lit'] != null) {
      try {
        return evaluate(Condition.parse(look['lit'], 'lit'), registry);
      } on FormatException {
        return null;
      }
    }
    if (link.steps.length != 1) return null;
    switch (link.steps.single) {
      case FlipStep(:final state, :final key):
        return registry.read(state, key: key) == true;
      case CallStep(:final command, :final params):
        final sets = registry.commandDescriptor(command)?.sets;
        if (sets == null || !params.containsKey(sets.value)) return null;
        final key = sets.key == null ? null : params[sets.key] as String?;
        return jsonEquals(
          registry.read(sets.state, key: key),
          params[sets.value],
        );
      default:
        return null;
    }
  }

  String? _unavailable(Reaction link) {
    for (final s in link.steps) {
      final command = switch (s) {
        CallStep(:final command) => command,
        FlipStep(:final state) => registry.setterOf(state),
        _ => null,
      };
      if (command == null) continue;
      return registry.whyUnavailable(command);
    }
    return null;
  }

  /// Whether [definition] is a link the engine can take, and what of the
  /// catalog it lacks; nothing is applied.
  LinkCheck check(Object? definition) {
    try {
      final link = Link.parse(definition);
      final missing = _missing(link);
      return (ok: missing.isEmpty, problems: const [], missing: missing);
    } on FormatException catch (e) {
      return (ok: false, problems: [e.message], missing: const []);
    }
  }

  void _setOwn(List<Object?> definitions, {Object? keepOrderOf}) {
    final next = <Map<String, Object?>>[];
    final problems = <String>[];
    final ids = <Object?>{};
    for (final d in definitions) {
      if (d is! Map) {
        problems.add('a link is an object');
        continue;
      }
      final m = freezeJson(d) as Map<String, Object?>;
      try {
        Link.parse(m);
      } on FormatException catch (e) {
        problems.add('${m['id'] ?? '?'}: ${e.message}');
      }
      if (!ids.add(m['id'])) problems.add('${m['id']}: id twice');
      next.add(m);
    }
    if (problems.isNotEmpty) {
      throw StateError('not taken: ${problems.join('; ')}');
    }
    if (keepOrderOf != null) {
      // An upsert keeps a replaced link where it was.
      final i = _own.indexWhere((l) => l['id'] == keepOrderOf);
      if (i >= 0) next.insert(i, next.removeLast());
    }
    // Saved first: a store that fails leaves the links as they were.
    store?.save(next);
    _own = next;
    _ownState.set(_own);
    _compose();
  }

  List<LinkProblem> _compose() {
    final own = {for (final l in _own) l['id']: l};
    final defs = <Object?>[
      for (final set in _sources.values)
        for (final d in set) own.remove(d['id']) ?? d,
      ...own.values,
    ];
    return problems = _apply(defs);
  }

  List<LinkProblem> _apply(List<Object?> definitions) {
    final problems = <LinkProblem>[];
    final next = <String, Link>{};
    final invalid = <String, String>{};
    for (final d in definitions) {
      final id = d is Map ? d['id'] as String? : null;
      try {
        final link = Link.parse(d);
        if (next.containsKey(link.id) || invalid.containsKey(link.id)) {
          throw FormatException('id ${link.id} twice');
        }
        next[link.id] = link;
      } on FormatException catch (e) {
        problems.add(LinkProblem(id, e.message));
        if (id != null && id.isNotEmpty) invalid[id] = e.message;
      }
    }
    for (final id in [..._links.keys]) {
      final now = next[id];
      if (now == null || !jsonEquals(now.json, _links[id]!.json)) {
        _deactivate(id);
      }
    }
    final gone = {..._links.keys, ..._invalid.keys}
      ..removeAll(next.keys)
      ..removeAll(invalid.keys);
    _links
      ..clear()
      ..addAll(next);
    _invalid
      ..clear()
      ..addAll(invalid);
    for (final id in gone) {
      _disabled.remove(id);
      _notes.remove(id);
      _statuses.remove(id);
      _status.remove(key: id);
    }
    registry.entitiesChanged(LinkWords.kind);
    _reconcile();
    return problems;
  }

  // --- Reconciling -----------------------------------------------------------

  bool _reconciling = false;
  bool _again = false;

  void _reconcile() {
    if (_reconciling) {
      _again = true;
      return;
    }
    _reconciling = true;
    try {
      do {
        _again = false;
        for (final id in _invalid.keys) {
          _setStatus(LinkStatus(id, LinkState.invalid, reason: _invalid[id]));
        }
        final ordered = [
          ..._links.values.where((l) => l is OwnState || l is OwnCommand),
          ..._links.values.where((l) => l is! OwnState && l is! OwnCommand),
        ];
        for (final link in ordered) {
          _reconcileOne(link);
        }
      } while (_again);
    } finally {
      _reconciling = false;
    }
  }

  void _reconcileOne(Link link) {
    final id = link.id;
    if (!link.enabled) {
      _deactivate(id);
      return _setStatus(LinkStatus(id, LinkState.off));
    }
    if (_disabled[id] case final why?) {
      _deactivate(id);
      return _setStatus(LinkStatus(id, LinkState.disabled, reason: why));
    }
    final List<String> missing;
    try {
      missing = _missing(link);
    } on FormatException catch (e) {
      _deactivate(id);
      return _setStatus(LinkStatus(id, LinkState.invalid, reason: e.message));
    }
    if (missing.isNotEmpty) {
      // An own word stays while it is live: what it lacks is only ever
      // something its steps call, checked when they run.
      _deactivate(id);
      return _setStatus(LinkStatus(id, LinkState.unresolved, missing: missing));
    }
    if (!_live.containsKey(id)) {
      try {
        _activate(link);
      } catch (e) {
        _deactivate(id);
        return _setStatus(LinkStatus(id, LinkState.invalid, reason: '$e'));
      }
    }
    _setStatus(LinkStatus(id, LinkState.active, reason: _notes[id]));
  }

  void _setStatus(LinkStatus s) {
    _statuses[s.id] = s;
    _status.set((
      state: s.state,
      missing: s.missing,
      reason: s.reason,
    ), key: s.id);
  }

  void _clearNote(String id) {
    if (_notes.remove(id) == null) return;
    if (_statuses[id] case final s? when s.state == LinkState.active) {
      _setStatus(LinkStatus(id, LinkState.active));
    }
  }

  void _note(String id, String why) {
    _notes[id] = why;
    if (_statuses[id] case final s? when s.state == LinkState.active) {
      _setStatus(LinkStatus(id, LinkState.active, reason: why));
    }
  }

  /// The names [link] needs that the catalog lacks, sorted.
  List<String> _missing(Link link) {
    final commands = <String>{};
    final states = <String>{};
    final facts = <String>{};
    final other = <String>{};

    void steps(List<Step> list) {
      for (final s in list) {
        switch (s) {
          case CallStep(:final command, :final params):
            commands.add(command);
            states.addAll(stateRefs(params));
          case FlipStep(:final state):
            states.add(state);
          case WaitStep():
            break;
          case WaitUntilStep(:final until):
            if (until.fact case final f?) facts.add(f.fact);
            if (until.condition case final c?) states.addAll(c.reads);
          case TemporarilyStep(:final until, steps: final inner):
            steps(inner);
            if (until?.fact case final f?) facts.add(f.fact);
            if (until?.condition case final c?) states.addAll(c.reads);
        }
      }
    }

    void trigger(Trigger t) {
      switch (t) {
        case FactTrigger(:final fact):
          facts.add(fact);
        case StateTrigger(:final state):
          states.add(state);
        case ExtensionTrigger(:final raw):
          final ext = _extensionOf(raw);
          if (ext == null) {
            other.add('trigger ${raw.keys.join('/')}');
          } else {
            trigger(ext.translate(raw));
          }
        case EveryTrigger() || AtTrigger() || ManualTrigger():
          break;
      }
    }

    switch (link) {
      case OwnState() || OwnCommand():
        break;
      case Reaction(:final triggers, :final only, steps: final s):
        triggers.forEach(trigger);
        if (only != null) states.addAll(only.reads);
        steps(s);
      case Binding(:final condition, :final anchor, :final holds):
        if (condition != null) states.addAll(condition.reads);
        if (anchor != null) {
          final kind = _anchors[anchor.kind];
          if (kind == null) {
            other.add('anchor ${anchor.kind}');
          } else if (!registry.hasEntity(kind.entityKind, anchor.entity)) {
            other.add('${kind.entityKind} ${anchor.entity}');
          } else {
            states.addAll(kind.condition(anchor.entity).reads);
          }
        }
        steps(holds);
      case Constraint(:final command, :final condition):
        if (command != null) commands.add(command);
        if (condition != null) states.addAll(condition.reads);
      case Interception(:final command, steps: final s):
        commands.add(command);
        steps(s);
    }
    return [
      for (final c in commands)
        if (registry.commandDescriptor(c) == null) c,
      for (final s in states)
        if (registry.stateDescriptor(s) == null) s,
      for (final f in facts)
        if (registry.factDescriptor(f) == null) f,
      ...other,
    ]..sort();
  }

  TriggerExtension? _extensionOf(Map<String, Object?> raw) {
    for (final k in raw.keys) {
      if (_extensions[k] case final e?) return e;
    }
    return null;
  }

  void _activate(Link link) {
    final live = switch (link) {
      final OwnState s => _activateOwnState(s),
      final OwnCommand c => _activateOwnCommand(c),
      final Reaction r => _LiveReaction(this, r, _resolveTriggers(r)),
      final Binding b => _LiveBinding(b, _bindingCondition(b)),
      final Constraint c => _LiveHandles(c, [
        registry.addGuard(
          c.id,
          (call) => _denies(c, call) ? c.reason : null,
          overridable: c.overridable,
        ),
      ]),
      final Interception i => _activateInterception(i),
    };
    _live[link.id] = live;
    switch (live) {
      case _LiveReaction r:
        r.start();
      case _LiveBinding b:
        _evalBinding(b);
      case _LiveHandles():
        break;
    }
  }

  void _deactivate(String id) {
    final live = _live.remove(id);
    if (live == null) return;
    switch (live) {
      case _LiveReaction r:
        r.stop();
      case _LiveBinding b:
        b.active = false;
        registry.dropLayersOf(id);
      case _LiveHandles h:
        for (final x in h.handles) {
          x.dispose();
        }
    }
  }

  _LiveHandles _activateOwnState(OwnState s) {
    var initial = _ownValues[s.state] ?? s.defaultValue;
    try {
      s.type.check(initial, registry);
    } on TypeMismatch {
      initial = s.defaultValue;
    }
    final writer = registry.defineState(
      StateDescriptor(s.state, type: s.type, meta: {'link': s.id}),
      by: linkPrincipal(s.id),
    );
    final Handle setter;
    try {
      setter = registry.defineCommand(
        CommandDescriptor(
          s.setter,
          params: ObjectType({'value': Field(s.type)}),
          // The registry sets it too, to apply a layer.
          callers: Callers({..._managers.rules, 'system': Access.allow}),
          sets: Sets(s.state),
          meta: {'link': s.id},
        ),
        (c) {
          _ownValues[s.state] = c.params['value'];
          writer.set(c.params['value']);
        },
      );
    } catch (_) {
      writer.dispose();
      rethrow;
    }
    _ownValues[s.state] = initial;
    writer.set(initial);
    return _LiveHandles(s, [setter, writer]);
  }

  _LiveHandles _activateOwnCommand(OwnCommand c) => _LiveHandles(c, [
    registry.defineCommand(
      CommandDescriptor(
        c.command,
        params: c.params,
        // The managers may; a definition's callers open it to more.
        callers: Callers({..._managers.rules, ...?c.callers?.rules}),
        meta: {'link': c.id},
      ),
      (call) async {
        if (call.cause.came(c.id)) {
          throw StateError('${c.command} calls itself');
        }
        final run = _Run(
          c,
          call.params,
          call.cause.child(call.id, by: linkPrincipal(c.id), through: c.id),
        );
        final failure = await _runSteps(run, c.steps);
        if (failure != null) throw StateError(failure);
      },
    ),
  ]);

  _LiveHandles _activateInterception(Interception i) {
    final d = registry.commandDescriptor(i.command)!;
    if (!d.interceptable) {
      throw FormatException('${i.command} is not interceptable');
    }
    return _LiveHandles(i, [
      registry.addBefore(
        i.command,
        i.id,
        (call, cause) async {
          final run = _Run(i, {
            'params': call.params,
            'by': call.by.toJson(),
          }, cause.withBy(linkPrincipal(i.id)));
          await _runSteps(run, i.steps);
        },
        priority: i.priority,
        timeout: i.timeout,
      ),
    ]);
  }

  List<_Resolved> _resolveTriggers(Reaction r) => [
    for (final t in r.triggers)
      switch (t) {
        ExtensionTrigger(:final raw) => () {
          final ext = _extensionOf(raw)!;
          final base = ext.translate(raw);
          return _Resolved(base, ext, raw, [
            ...base.throttles,
            ...t.throttles,
          ], base.once || t.once);
        }(),
        _ => _Resolved(t, null, const {}, t.throttles, t.once),
      },
  ];

  Condition _bindingCondition(Binding b) => switch (b.anchor) {
    final a? => _anchors[a.kind]!.condition(a.entity),
    null => b.condition!,
  };

  bool _denies(Constraint c, PendingCall call) {
    if (!c.appliesToPrincipal(call.by)) return false;
    if (!c.targets(call.command.name, call.params)) return false;
    return c.condition == null || evaluate(c.condition!, registry);
  }

  // --- Commands of the engine ------------------------------------------------

  static LinkOutcome _ran(bool ran, {String? reason, String? failure}) =>
      (ran: ran, denies: null, reason: reason, failure: failure);

  Future<LinkOutcome> _press(CommandCallOf<PressLink> call) async {
    final live = _live[call.params.link];
    if (live is! _LiveReaction) return _ran(false, reason: 'not active');
    for (final (i, t) in live.triggers.indexed) {
      if (t.base is! ManualTrigger) continue;
      final why = live.fire(
        i,
        call.params.args ?? const <String, Object?>{},
        by: call.by,
        parent: call.id,
        from: call.cause,
        read: (s, k) => registry.read(s, key: k),
      );
      if (why != null) return _ran(false, reason: why);
      // With wait, the answer comes when the run has ended: a button shows
      // that it works, then that it worked or why not.
      final run = live.lastStarted;
      if (!call.params.wait || run == null) return _ran(true);
      return _ran(true, failure: await run.done.future);
    }
    return _ran(false, reason: 'not pressable');
  }

  Future<LinkOutcome> _try(CommandCallOf<LinkRef> call) async {
    final id = call.params.link;
    final live = _live[id];
    switch (live) {
      case _LiveReaction r:
        final run = _Run(
          r.link,
          const <String, Object?>{},
          Cause(
            linkPrincipal(id),
            parent: call.id,
            chain: [...call.cause.chain, id],
            test: true,
          ),
        );
        final failure = await _runSteps(run, r.link.steps);
        return failure == null ? _ran(true) : _ran(false, reason: failure);
      case _LiveHandles(link: final Constraint c):
        final on = c.condition == null || evaluate(c.condition!, registry);
        return (
          ran: null,
          denies: on,
          reason: on ? c.reason : null,
          failure: null,
        );
      default:
        return _ran(false, reason: 'nothing to try');
    }
  }

  // --- Evaluation ------------------------------------------------------------

  void _onTick(Tick t) {
    for (final c in t.changes) {
      if (c.removed) {
        _view.remove((c.state, c.key));
      } else {
        _view[(c.state, c.key)] = c.value;
      }
    }
    final changed = {for (final c in t.changes) c.state};
    for (final live in [..._live.values]) {
      switch (live) {
        case _LiveReaction r:
          for (final c in t.changes) {
            r.onChange(c);
          }
          for (final f in t.facts) {
            r.onFact(f);
          }
        case _LiveBinding b:
          if (b.condition.reads.any(changed.contains)) _evalBinding(b);
        case _LiveHandles():
          break;
      }
    }
    for (final w in [..._waiters]) {
      w.check(t, _readView);
    }
  }

  void _evalBinding(_LiveBinding b) {
    if (_live[b.link.id] != b) return;
    final on = evaluateWith(b.condition, _readView);
    if (on && !b.active) {
      b.active = true;
      for (final hold in b.link.holds) {
        try {
          final params =
              resolve(hold.params, null, registry) as Map<String, Object?>;
          final d = registry.commandDescriptor(hold.command);
          final sets = d?.sets;
          if (sets == null) {
            _note(b.link.id, '${hold.command} sets no state; not held');
            continue;
          }
          registry.pushLayer(
            sets.state,
            key: sets.key == null ? null : params[sets.key] as String?,
            value: params[sets.value],
            owner: b.link.id,
            by: linkPrincipal(b.link.id),
            priority: b.link.priority,
            chain: [b.link.id],
          );
        } catch (e) {
          _note(b.link.id, '${hold.command}: $e');
        }
      }
    } else if (!on && b.active) {
      b.active = false;
      registry.dropLayersOf(b.link.id);
    }
  }

  void _onLayer(LayerEvent e) {
    final live = _live[e.owner];
    if (live is _LiveBinding) {
      switch (e.outcome) {
        case LayerOutcome.refused:
          _note(e.owner, 'held value refused: ${e.reason}');
        case LayerOutcome.orphaned:
          _note(e.owner, '${e.state} lost its setter');
        default:
          break;
      }
    }
  }

  // --- Runs ------------------------------------------------------------------

  /// Runs [steps]; answers why it stopped early, or null.
  Future<String?> _runSteps(_Run run, List<Step> steps) async {
    try {
      for (final s in steps) {
        if (run.isCancelled) return 'stopped';
        final failure = await _step(run, s);
        if (failure != null) {
          _note(run.link.id, failure);
          return run.failure = failure;
        }
      }
      _clearNote(run.link.id);
      return null;
    } catch (e, st) {
      _onError(e, st);
      _note(run.link.id, '$e');
      return run.failure = '$e';
    } finally {
      run.stepsDone = true;
      run.maybeFinish();
    }
  }

  Future<String?> _step(_Run run, Step s) async {
    switch (s) {
      case CallStep():
        final r = await _call(run, s);
        if (r is CallDone || s.orContinue) return null;
        return '${s.command}: $r';
      case FlipStep(:final state, :final key, :final orContinue):
        final setter = registry.setterOf(state);
        final sets = setter == null
            ? null
            : registry.commandDescriptor(setter)?.sets;
        if (setter == null || sets == null) return '$state has no setter';
        final now = registry.effective(state, key: key).value;
        final r = await registry.call(
          setter,
          {sets.value: now != true, ?sets.key: key},
          by: run.cause.by,
          cause: run.cause,
        );
        if (r is CallDone || orContinue) return null;
        return '$state: $r';
      case WaitStep(:final duration):
        await Future.any([
          Future<void>.delayed(duration),
          run.cancelled.future,
        ]);
        return null;
      case WaitUntilStep(:final until, :final timeout, :final orContinue):
        final met = await _until(until, run, timeout: timeout);
        if (met || orContinue || run.isCancelled) return null;
        return 'waited $timeout in vain';
      case TemporarilyStep():
        _temporarily(run, s);
        return null;
    }
  }

  Future<CallResult<Object?>> _call(_Run run, CallStep s) {
    final params = resolve(s.params, run.data, registry);
    return registry.call(
      s.command,
      params is Map<String, Object?> ? params : const {},
      by: run.cause.by,
      cause: run.cause,
    );
  }

  void _temporarily(_Run run, TemporarilyStep t) {
    final owner = '${run.link.id}#${run.id}#${run.temporaries++}';
    run.open++;
    for (final c in t.steps) {
      final d = registry.commandDescriptor(c.command);
      final sets = d?.sets;
      if (sets == null) {
        unawaited(_call(run, c));
        continue;
      }
      try {
        final params =
            resolve(c.params, run.data, registry) as Map<String, Object?>;
        registry.pushLayer(
          sets.state,
          key: sets.key == null ? null : params[sets.key] as String?,
          value: params[sets.value],
          owner: owner,
          by: run.cause.by,
          priority: switch (run.link) {
            Binding(:final priority) => priority,
            _ => 0,
          },
          ttl: t.holdFor,
          chain: run.cause.chain,
        );
      } catch (e) {
        _note(run.link.id, '${c.command}: $e');
      }
    }
    void end() {
      registry.dropLayersOf(owner);
      if (run.isCancelled) return;
      run.open--;
      run.maybeFinish();
    }

    run.onCancel.add(() => registry.dropLayersOf(owner));
    if (t.holdFor case final d?) {
      Future.any([Future<void>.delayed(d), run.cancelled.future])
          .then((_) => end());
    } else {
      _until(t.until!, run).then((_) => end());
    }
  }

  /// Waits for [until] (or [timeout], or the run's end); answers whether it
  /// came.
  Future<bool> _until(Until until, _Run run, {Duration? timeout}) {
    if (until.condition case final c? when evaluate(c, registry)) {
      return Future.value(true);
    }
    final w = _Waiter(until);
    _waiters.add(w);
    return Future.any<bool>([
      w.done.future.then((_) => true),
      run.cancelled.future.then((_) => false),
      if (timeout != null) Future<bool>.delayed(timeout, () => false),
    ]).whenComplete(() => _waiters.remove(w));
  }

  void _disable(String id, String why) {
    if (_disabled.containsKey(id)) return;
    _disabled[id] = why;
    _disabledFact.emit((link: id, reason: why));
    _reconcile();
  }

  /// Stops every link and withdraws the engine from the registry.
  Future<void> dispose() async {
    for (final id in [..._live.keys]) {
      _deactivate(id);
    }
    for (final s in _subs) {
      await s.cancel();
    }
    for (final h in _handles.reversed) {
      h.dispose();
    }
  }
}

// --- Live links -------------------------------------------------------------

sealed class _Live {
  const _Live(this.link);
  final Link link;
}

final class _LiveHandles extends _Live {
  const _LiveHandles(super.link, this.handles);
  final List<Handle> handles;
}

final class _LiveBinding extends _Live {
  _LiveBinding(Binding super.link, this.condition);
  final Condition condition;

  /// Holding its layers. A layer dropped as overridden is not pushed again
  /// until the condition turns false and then true: it stays active.
  bool active = false;

  @override
  Binding get link => super.link as Binding;
}

/// A trigger with its extension resolved.
final class _Resolved {
  _Resolved(this.base, this.ext, this.options, this.throttles, this.once);
  final Trigger base;
  final TriggerExtension? ext;
  final Map<String, Object?> options;
  final List<Throttle> throttles;
  final bool once;
  final Map<String, DateTime> lastBy = {};
}

final class _LiveReaction extends _Live {
  _LiveReaction(this.engine, Reaction super.link, this.triggers);

  final Links engine;
  final List<_Resolved> triggers;
  final List<_Run> running = [];
  final Queue<_Run> queued = Queue();
  final Set<int> fired = {};
  final ListQueue<DateTime> recentRuns = ListQueue();
  final List<Timer> timers = [];
  final Map<(int, String?), Timer> holding = {};
  bool stopped = false;

  @override
  Reaction get link => super.link as Reaction;

  Registry get registry => engine.registry;

  void start() {
    for (final (i, t) in triggers.indexed) {
      switch (t.base) {
        case EveryTrigger(:final interval):
          timers.add(
            Timer.periodic(
              interval,
              (_) => fire(i, {
                'at': engine.registry.clock.now().toUtc().toIso8601String(),
              }),
            ),
          );
        case final AtTrigger a:
          _scheduleAt(i, a);
        default:
          break;
      }
    }
  }

  void _scheduleAt(int i, AtTrigger a) {
    if (stopped) return;
    final now = engine.registry.clock.now();
    final next = a.nextAfter(now);
    timers.add(
      Timer(next.difference(now), () {
        fire(i, {'at': next.toUtc().toIso8601String()});
        _scheduleAt(i, a);
      }),
    );
  }

  void onChange(StateChange c) {
    for (final (i, t) in triggers.indexed) {
      final base = t.base;
      if (base is! StateTrigger || base.state != c.state) continue;
      if (base.key != null && base.key != c.key) continue;
      final slot = (i, c.key);
      if (base.holdFor != null) {
        if (holding[slot] case final timer? when !base.holds(c.value)) {
          timer.cancel();
          holding.remove(slot);
        }
      }
      if (!base.fires(c.removed ? null : c.previous, c.value)) continue;
      final data = {
        'state': c.state,
        'key': ?c.key,
        'value': c.value,
        'previous': c.previous,
      };
      if (base.holdFor case final d?) {
        holding[slot]?.cancel();
        holding[slot] = Timer(d, () {
          holding.remove(slot);
          fire(i, data, parent: c.id, from: c.cause, origin: c.cause.by);
        });
      } else {
        fire(i, data, parent: c.id, from: c.cause, origin: c.cause.by);
      }
    }
  }

  void onFact(FactMessage f) {
    for (final (i, t) in triggers.indexed) {
      final base = t.base;
      if (base is! FactTrigger || base.fact != f.fact) continue;
      if (!base.where.matches(f.payload)) continue;
      fire(i, f.payload, parent: f.id, from: f.cause, origin: f.cause.by);
    }
  }

  /// Fires trigger [i] with [data]; answers why it did not run, or null.
  ///
  /// Conditions read [read]: the engine's view by default; a press reads
  /// the registry now.
  ///
  /// The run acts for [by] when given (a press); else for [origin], the one
  /// who caused the trigger, when the managers do not count them in (an
  /// audience's message): their rights, never the link's. Anyone else's
  /// trigger runs as the link, with no more rights than the link has.
  String? fire(
    int i,
    Object? data, {
    Principal? by,
    String? parent,
    Cause? from,
    Principal? origin,
    StateReader? read,
  }) {
    if (stopped) return 'stopped';
    final id = link.id;
    if (from != null && from.came(id)) return 'loop';
    final t = triggers[i];
    var payload = data;
    var principal =
        by ??
        (origin != null &&
                origin != Principal.system &&
                !engine._managers.allows(origin)
            ? origin
            : null);
    if (t.ext?.accept case final accept?) {
      final hit = accept(data, t.options);
      if (hit == null) return 'not this trigger';
      payload = hit.data;
      principal = hit.by ?? principal;
    }
    if (link.only case final c?
        when !evaluateWith(c, read ?? engine._readView)) {
      return 'conditions';
    }
    // Everything that turns a firing away is asked first: a firing that
    // does not run spends no once, no throttle and no rate.
    switch (link.mode) {
      case RunMode.single when running.isNotEmpty:
        return 'running';
      case RunMode.queue
          when running.isNotEmpty && queued.length >= link.queueLimit:
        return 'queue full';
      default:
        break;
    }
    final now = engine.registry.clock.now();
    String budget(Throttle th) =>
        '${th.every.inMilliseconds}:${th.per == null ? '' : jsonAt(payload, th.per!)}';
    for (final th in t.throttles) {
      final last = t.lastBy[budget(th)];
      if (last != null && now.difference(last) < th.every) return 'throttled';
    }
    if (t.once && fired.contains(i)) return 'once';
    while (recentRuns.isNotEmpty &&
        now.difference(recentRuns.first) >= engine.rateWindow) {
      recentRuns.removeFirst();
    }
    if (recentRuns.length >= engine.rateLimit) {
      engine._disable(
        id,
        'more than ${engine.rateLimit} runs in ${engine.rateWindow.inSeconds} s',
      );
      return 'disabled';
    }
    for (final th in t.throttles) {
      t.lastBy[budget(th)] = now;
    }
    if (t.once) fired.add(i);
    recentRuns.add(now);
    final cause = Cause(
      principal ?? linkPrincipal(id),
      parent: parent,
      chain: [...?from?.chain, id],
      test: from?.test ?? false,
    );
    final run = _Run(link, payload, cause)..onFinish = _finished;
    switch (link.mode) {
      case RunMode.restart:
        for (final r in [...running]) {
          r.cancel();
        }
      case RunMode.queue when running.isNotEmpty:
        queued.add(run);
        lastStarted = run;
        return null;
      default:
        break;
    }
    lastStarted = run;
    _start(run);
    return null;
  }

  /// The run the last firing started or queued.
  _Run? lastStarted;

  void _start(_Run run) {
    running.add(run);
    engine._runSteps(run, link.steps);
  }

  void _finished(_Run run) {
    running.remove(run);
    if (!stopped && running.isEmpty && queued.isNotEmpty) {
      _start(queued.removeFirst());
    }
  }

  /// Stops the runs, and ends the queued ones as stopped: a press waiting
  /// for one is answered.
  void stopAll() {
    final dropped = [...queued];
    queued.clear();
    for (final r in [...dropped, ...running]) {
      r.cancel();
    }
  }

  void stop() {
    stopped = true;
    for (final t in timers) {
      t.cancel();
    }
    for (final t in holding.values) {
      t.cancel();
    }
    holding.clear();
    stopAll();
  }
}

/// One run of steps: of a reaction, an own command or an interception.
final class _Run {
  _Run(this.link, this.data, this.cause);

  final Link link;

  /// What `$trigger` refers to.
  final Object? data;

  /// The cause of every call it makes.
  final Cause cause;
  final String id = newId();
  final Completer<void> cancelled = Completer();

  /// Ends with why the run stopped early, or null.
  final Completer<String?> done = Completer();

  /// Why the steps stopped early, or null.
  String? failure;
  final List<void Function()> onCancel = [];
  void Function(_Run)? onFinish;

  /// Temporaries made, and those still holding.
  int temporaries = 0;
  int open = 0;
  bool stepsDone = false;
  bool _finished = false;

  bool get isCancelled => cancelled.isCompleted;

  void cancel() {
    if (isCancelled) return;
    cancelled.complete();
    for (final f in onCancel) {
      f();
    }
    open = 0;
    maybeFinish();
  }

  void maybeFinish() {
    if (_finished || !(stepsDone || isCancelled) || open > 0) return;
    _finished = true;
    done.complete(isCancelled ? (failure ?? 'stopped') : failure);
    onFinish?.call(this);
  }
}

/// A wait for a fact or a condition.
final class _Waiter {
  _Waiter(this.until);
  final Until until;
  final Completer<void> done = Completer();

  void check(Tick t, StateReader read) {
    if (done.isCompleted) return;
    if (until.fact case final f?) {
      if (t.facts.any((m) => m.fact == f.fact && f.where.matches(m.payload))) {
        done.complete();
      }
    } else if (until.condition case final c? when evaluateWith(c, read)) {
      done.complete();
    }
  }
}
