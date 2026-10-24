/// The words a links engine puts in a registry (SPEC §13), by name: its
/// clients (an agent's tools, a host's buttons) call them so without
/// knowing the engine, and the engine defines exactly these.
///
/// It imports nothing: whoever speaks to links may use it.
library;

abstract final class LinkWords {
  /// The entity kind of links, and the kind of the principal the engine
  /// acts as.
  static const kind = 'link';

  /// What the user's own commands and states are named under.
  static const ownPrefix = 'my.';

  // States and facts.
  static const status = 'links.status';
  static const own = 'links.own';
  static const disabled = 'links.disabled';

  // Commands on one link, by its id in the param `link`.
  static const press = 'links.press';
  static const tryOut = 'links.try';
  static const reset = 'links.reset';
  static const stop = 'links.stop';
  static const enabledSet = 'links.enabled.set';

  // Commands on the user's own links.
  static const check = 'links.check';
  static const set = 'links.set';
  static const upsert = 'links.upsert';
  static const remove = 'links.remove';

  /// Every name the engine takes in the catalog: two engines on one
  /// registry would take the same.
  static const all = [
    status,
    own,
    disabled,
    press,
    tryOut,
    reset,
    stop,
    enabledSet,
    check,
    set,
    upsert,
    remove,
  ];
}

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
