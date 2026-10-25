/// The words a links engine puts in a registry (SPEC §13), typed (SPEC
/// §18): its clients (an agent's tools, a host's buttons) call them so
/// without knowing the engine, and the engine defines exactly these.
///
/// It imports only the registry's types and words: whoever speaks to links
/// may use it.
library;

import 'registry/types.dart';
import 'registry/words.dart';

/// Where a link stands.
enum LinkState {
  /// Working.
  active,

  /// Names something the catalog lacks; waits for it.
  unresolved,

  /// Turned off in its definition.
  off,

  /// Turned off while running: too many runs, or by `links.enabled.set`.
  disabled,

  /// Its definition is wrong.
  invalid,
}

/// A link's status, as `links.status` holds it by link.
typedef LinkStanding = ({
  LinkState state,
  List<String>? missing,
  String? reason,
});

/// A link the engine turned off, and why.
typedef LinkDisabled = ({String link, String reason});

/// A control as `links.controls` holds it (SPEC §13.12): the link to
/// press, its name, how the host draws it (its manual trigger's options),
/// whether it is lit and why pressing it cannot work now.
typedef ControlView = ({
  String id,
  String? name,
  Map<String, Object?> look,
  bool? lit,
  String? unavailable,
});

/// Press a link (a reaction with a manual trigger): its trigger's [args];
/// with [wait], the answer comes when the run has ended.
typedef PressLink = ({String link, Object? args, bool wait});

/// One link, by id.
typedef LinkRef = ({String link});

typedef EnableLink = ({String link, bool on});

/// A link's definition, as JSON.
typedef LinkDefinition = ({Object? link});

/// The user's own links, as JSON definitions.
typedef OwnLinks = ({List<Object?> links});

typedef RemoveLink = ({String id});

/// What a press or a try came to: whether it [ran] (or, for a constraint,
/// whether it [denies]), why not, and how a run waited for failed.
typedef LinkOutcome = ({
  bool? ran,
  bool? denies,
  String? reason,
  String? failure,
});

/// A definition checked: what is wrong in it, what it names that the
/// catalog lacks.
typedef LinkCheck = ({bool ok, List<String> problems, List<String> missing});

abstract final class LinkWords {
  /// The entity kind of links, and the kind of the principal the engine
  /// acts as.
  static const kind = 'link';

  /// What the user's own commands and states are named under.
  static const ownPrefix = 'my.';

  // States and facts.
  static const StateWord<LinkStanding> status = _State(
    'links.status',
    RecordShape(
      {
        'state': Part(EnumShape(LinkState.values)),
        'missing': Part(ListShape(Plain(TextType())), optional: true),
        'reason': Part(Plain(TextType()), optional: true),
      },
      to: _standingTo,
      from: _standingFrom,
    ),
    key: kind,
  );

  /// The controls there are now, in the order of the links: what a
  /// client over remote draws as buttons, and presses with [press].
  static const StateWord<List<ControlView>> controls = _State(
    'links.controls',
    ListShape(
      RecordShape(
        {
          'id': Part(Plain(TextType())),
          'name': Part(Plain(TextType()), optional: true),
          'look': Part(MapShape(Plain(AnyType())), defaultValue: {}),
          'lit': Part(Plain(BoolType()), optional: true),
          'unavailable': Part(Plain(TextType()), optional: true),
        },
        to: _controlTo,
        from: _controlFrom,
      ),
    ),
  );
  static const StateWord<List<Object?>> own = _State(
    'links.own',
    ListShape(Plain(AnyType())),
  );
  static const FactWord<LinkDisabled> disabled = _Fact(
    'links.disabled',
    RecordShape(
      {'link': Part(Plain(TextType())), 'reason': Part(Plain(TextType()))},
      to: _disabledTo,
      from: _disabledFrom,
    ),
  );

  // Commands on one link, by its id in the param `link`.
  static const CommandWord<PressLink, LinkOutcome> press = _Command(
    'links.press',
    RecordShape(
      {
        'link': Part(Plain(RefType(kind))),
        'args': Part(Plain(AnyType()), optional: true),
        'wait': Part(Plain(BoolType()), defaultValue: false),
      },
      to: _pressTo,
      from: _pressFrom,
    ),
    returns: _outcome,
  );
  static const CommandWord<LinkRef, LinkOutcome> tryOut = _Command(
    'links.try',
    _link,
    returns: _outcome,
  );
  static const CommandWord<LinkRef, void> reset = _Command(
    'links.reset',
    _link,
  );
  static const CommandWord<LinkRef, void> stop = _Command('links.stop', _link);
  static const CommandWord<EnableLink, void> enabledSet = _Command(
    'links.enabled.set',
    RecordShape(
      {'link': Part(Plain(RefType(kind))), 'on': Part(Plain(BoolType()))},
      to: _enableTo,
      from: _enableFrom,
    ),
  );

  // Commands on the user's own links.
  static const CommandWord<LinkDefinition, LinkCheck> check = _Command(
    'links.check',
    _definition,
    returns: RecordShape(
      {
        'ok': Part(Plain(BoolType())),
        'problems': Part(ListShape(Plain(TextType()))),
        'missing': Part(ListShape(Plain(TextType()))),
      },
      to: _checkTo,
      from: _checkFrom,
    ),
  );
  static const CommandWord<OwnLinks, void> set = _Command(
    'links.set',
    RecordShape(
      {'links': Part(ListShape(Plain(AnyType())))},
      to: _ownTo,
      from: _ownFrom,
    ),
  );
  static const CommandWord<LinkDefinition, void> upsert = _Command(
    'links.upsert',
    _definition,
  );
  static const CommandWord<RemoveLink, void> remove = _Command(
    'links.remove',
    RecordShape(
      {'id': Part(Plain(TextType()))},
      to: _removeTo,
      from: _removeFrom,
    ),
  );

  /// Every name the engine takes in the catalog: two engines on one
  /// registry would take the same.
  static final List<String> all = [
    status.name,
    own.name,
    disabled.name,
    for (final c in <CommandWord<Object?, Object?>>[
      press,
      tryOut,
      reset,
      stop,
      enabledSet,
      check,
      set,
      upsert,
      remove,
    ])
      c.name,
  ];
}

final class _State<T> implements StateWord<T> {
  const _State(this.name, this.shape, {this.key});
  @override
  final String name;
  @override
  final Shape<T> shape;
  @override
  final String? key;
}

final class _Fact<T> implements FactWord<T> {
  const _Fact(this.name, this.shape);
  @override
  final String name;
  @override
  final Shape<T> shape;
}

final class _Command<P, R> implements CommandWord<P, R> {
  const _Command(this.name, this.params, {this.returns});
  @override
  final String name;
  @override
  final RecordShape<P> params;
  @override
  final Shape<R>? returns;
}

const _link = RecordShape<LinkRef>(
  {'link': Part(Plain(RefType(LinkWords.kind)))},
  to: _linkTo,
  from: _linkFrom,
);
const _definition = RecordShape<LinkDefinition>(
  {'link': Part(Plain(AnyType()))},
  to: _definitionTo,
  from: _definitionFrom,
);
const _outcome = RecordShape<LinkOutcome>(
  {
    'ran': Part(Plain(BoolType()), optional: true),
    'denies': Part(Plain(BoolType()), optional: true),
    'reason': Part(Plain(TextType()), optional: true),
    'failure': Part(Plain(TextType()), optional: true),
  },
  to: _outcomeTo,
  from: _outcomeFrom,
);

Map<String, Object?> _standingTo(LinkStanding s) => {
  'state': s.state,
  'missing': s.missing == null || s.missing!.isEmpty ? null : s.missing,
  'reason': s.reason,
};
LinkStanding _standingFrom(Map<String, Object?> m) => (
  state: m['state']! as LinkState,
  missing: m['missing'] as List<String>?,
  reason: m['reason'] as String?,
);
Map<String, Object?> _disabledTo(LinkDisabled d) => {
  'link': d.link,
  'reason': d.reason,
};
LinkDisabled _disabledFrom(Map<String, Object?> m) =>
    (link: m['link']! as String, reason: m['reason']! as String);
Map<String, Object?> _pressTo(PressLink p) => {
  'link': p.link,
  'args': p.args,
  'wait': p.wait,
};
PressLink _pressFrom(Map<String, Object?> m) =>
    (link: m['link']! as String, args: m['args'], wait: m['wait']! as bool);
Map<String, Object?> _linkTo(LinkRef l) => {'link': l.link};
LinkRef _linkFrom(Map<String, Object?> m) => (link: m['link']! as String);
Map<String, Object?> _enableTo(EnableLink e) => {'link': e.link, 'on': e.on};
EnableLink _enableFrom(Map<String, Object?> m) =>
    (link: m['link']! as String, on: m['on']! as bool);
Map<String, Object?> _definitionTo(LinkDefinition d) => {'link': d.link};
LinkDefinition _definitionFrom(Map<String, Object?> m) => (link: m['link']);
Map<String, Object?> _ownTo(OwnLinks o) => {'links': o.links};
OwnLinks _ownFrom(Map<String, Object?> m) =>
    (links: m['links']! as List<Object?>);
Map<String, Object?> _removeTo(RemoveLink r) => {'id': r.id};
RemoveLink _removeFrom(Map<String, Object?> m) => (id: m['id']! as String);
Map<String, Object?> _outcomeTo(LinkOutcome o) => {
  'ran': o.ran,
  'denies': o.denies,
  'reason': o.reason,
  'failure': o.failure,
};
LinkOutcome _outcomeFrom(Map<String, Object?> m) => (
  ran: m['ran'] as bool?,
  denies: m['denies'] as bool?,
  reason: m['reason'] as String?,
  failure: m['failure'] as String?,
);
Map<String, Object?> _checkTo(LinkCheck c) => {
  'ok': c.ok,
  'problems': c.problems,
  'missing': c.missing,
};
LinkCheck _checkFrom(Map<String, Object?> m) => (
  ok: m['ok']! as bool,
  problems: m['problems']! as List<String>,
  missing: m['missing']! as List<String>,
);

/// How links are written, for people and agents (SPEC §13). A test holds
/// it to the keys the parser reads.
const linkGuide = '''
A link is a JSON object with an id and one of these shapes.

Reaction: {id, when: [trigger...], only?: condition, mode?: single|restart|queue, queueLimit?: 10, do: [step...]}
Binding: {id, while: condition, hold: [call...], priority?} — only commands that set a state;
  or anchor: {kind: entity} instead of while: held while the host says that entity is in force
Constraint: {id, deny: {command?, where?, namespace?}, callers?: [kind...], while?: condition, reason, overridable?}
Interception: {id, before: {command}, do: [step...], timeout: "30s", priority?}
Own command: {id, command: "name", params?: {p: {type, optional?, default?, ...}}, callers?, do: [step...]} — callable as my.name by the managers; callers open it to more
Own state: {id, state: "name", values?: [..], default?} — a flag (or a mode), set by my.name.set {value}
Any link: enabled: false turns it off; name is how people see it.

Triggers: {fact: name, where?: {field: test}} | {state: name, key?, becomes|leaves: test, for?: "20m"}
  | {state: name, changes: {from?, to?}} | {every: "15m"} | {at: "20:00", days?: [1..7]}
  | {manual: {...look}} — pressed with links.press — and the host's own (see describe).
  Options on any: throttle: {every: "2m", per: "\$trigger.path"}, once: true.
Conditions: [{state, key?, is|not|in|<|<=|>|>=: value}...] (all) or {any: [...]}.
Steps: {call: command, params?, orContinue?} | {flip: bool state, key?, orContinue?} | {wait: "5s"}
  | {waitUntil: {fact: ...} or condition, timeout, orContinue?}
  | {temporarily: {for|until, do: [call...]}}.
Params may hold "\$trigger.path", "\$state.name[key]" and text with {path}.
Durations: 500ms, 15s, 2m, 1h.
''';

Map<String, Object?> _controlTo(ControlView c) => {
  'id': c.id,
  'name': ?c.name,
  'look': c.look,
  'lit': ?c.lit,
  'unavailable': ?c.unavailable,
};
ControlView _controlFrom(Map<String, Object?> m) => (
  id: m['id']! as String,
  name: m['name'] as String?,
  look: (m['look'] as Map?)?.cast<String, Object?>() ?? const {},
  lit: m['lit'] as bool?,
  unavailable: m['unavailable'] as String?,
);
