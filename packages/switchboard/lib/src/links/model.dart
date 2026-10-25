import '../link_words.dart';
import '../registry/cause.dart';
import '../registry/descriptors.dart';
import '../registry/ids.dart';
import '../registry/json.dart';
import '../registry/types.dart';

/// Links are data (SPEC §13): parsed from JSON values, kept as given.
///
/// Every class here is immutable and knows nothing of the registry; the
/// engine resolves the names in it against the catalog.

Never _bad(String what) => throw FormatException(what);

Map<String, Object?> _map(Object? v, String what) => switch (v) {
  final Map<Object?, Object?> m => m.cast<String, Object?>(),
  _ => _bad('$what: expected an object'),
};

List<Object?> _list(Object? v) => switch (v) {
  null => const [],
  final List<Object?> l => l,
  final x => [x],
};

String _str(Object? v, String what) =>
    v is String && v.isNotEmpty ? v : _bad('$what: expected text');

String _name(Object? v, String what) {
  final s = _str(v, what);
  if (!isValidName(s)) _bad('$what: $s is not a dotted lower-case name');
  return s;
}

/// A duration in a link: milliseconds, or text like `15s`, `2m`, `1h`,
/// `500ms`.
Duration parseDuration(Object? v, String what) {
  if (v is int && v >= 0) return Duration(milliseconds: v);
  if (v is String) {
    final m = RegExp(r'^(\d+)(ms|s|m|h)$').firstMatch(v.trim());
    if (m != null) {
      final n = int.parse(m[1]!);
      return switch (m[2]) {
        'ms' => Duration(milliseconds: n),
        's' => Duration(seconds: n),
        'm' => Duration(minutes: n),
        _ => Duration(hours: n),
      };
    }
  }
  _bad('$what: expected a duration like 15s');
}

// --- Tests on values ----------------------------------------------------------

/// A comparison (SPEC §13.3): `is`, `not`, `in`, `<`, `<=`, `>`, `>=`.
enum Op {
  isEqual('is'),
  not('not'),
  isIn('in'),
  lt('<'),
  le('<='),
  gt('>'),
  ge('>=');

  const Op(this.symbol);
  final String symbol;

  static Op? of(String s) {
    for (final o in values) {
      if (o.symbol == s) return o;
    }
    return null;
  }
}

/// One comparison of a value with an operand.
final class ValueTest {
  const ValueTest(this.op, this.operand);

  /// A literal means `is`; an object with one operator key means that.
  factory ValueTest.parse(Object? v, String what) {
    if (v is Map && v.length == 1) {
      final key = v.keys.single;
      if (key is String) {
        final op = Op.of(key);
        if (op != null) {
          final operand = v[key];
          if (op == Op.isIn && operand is! List) _bad('$what: in takes a list');
          if (op.index >= Op.lt.index && operand is! num) {
            _bad('$what: ${op.symbol} takes a number');
          }
          return ValueTest(op, freezeJson(operand));
        }
      }
    }
    return ValueTest(Op.isEqual, freezeJson(v));
  }

  final Op op;
  final Object? operand;

  bool matches(Object? value) => switch (op) {
    Op.isEqual => jsonEquals(value, operand),
    Op.not => !jsonEquals(value, operand),
    Op.isIn => (operand as List).any((o) => jsonEquals(o, value)),
    Op.lt => value is num && value < (operand as num),
    Op.le => value is num && value <= (operand as num),
    Op.gt => value is num && value > (operand as num),
    Op.ge => value is num && value >= (operand as num),
  };

  Object? toJson() => op == Op.isEqual ? operand : {op.symbol: operand};
}

/// Tests on fields of a value: path → test, all must hold.
final class Filter {
  const Filter(this.tests);

  factory Filter.parse(Object? v, String what) {
    if (v == null) return const Filter({});
    final m = _map(v, what);
    return Filter({
      for (final e in m.entries)
        e.key: ValueTest.parse(e.value, '$what.${e.key}'),
    });
  }

  final Map<String, ValueTest> tests;

  bool matches(Object? value) =>
      tests.entries.every((e) => e.value.matches(jsonAt(value, e.key)));
}

// --- Conditions ---------------------------------------------------------------

/// A condition over committed state (SPEC §13.3).
sealed class Condition {
  const Condition();

  /// A list means all; `{any: [...]}` means at least one; else one test of
  /// a state: `{state, key?, is | not | in | < | <= | > | >=}`.
  static Condition parse(Object? v, String what) {
    if (v is List) {
      return AllOf([
        for (var i = 0; i < v.length; i++) Condition.parse(v[i], '$what.$i'),
      ]);
    }
    final m = _map(v, what);
    if (m.containsKey('any')) {
      final l = _list(m['any']);
      return AnyOf([
        for (var i = 0; i < l.length; i++)
          Condition.parse(l[i], '$what.any.$i'),
      ]);
    }
    final state = _name(m['state'], '$what.state');
    final key = m['key'] as String?;
    final ops = [
      for (final k in m.keys)
        if (Op.of(k) != null) k,
    ];
    if (ops.length != 1) _bad('$what: one of is, not, in, <, <=, >, >=');
    return StateIs(
      state,
      key,
      ValueTest.parse({ops.single: m[ops.single]}, what),
    );
  }

  /// The states it reads.
  Set<String> get reads;
}

final class StateIs extends Condition {
  const StateIs(this.state, this.key, this.test);

  final String state;
  final String? key;
  final ValueTest test;

  @override
  Set<String> get reads => {state};
}

final class AllOf extends Condition {
  const AllOf(this.all);
  final List<Condition> all;

  @override
  Set<String> get reads => {for (final c in all) ...c.reads};
}

final class AnyOf extends Condition {
  const AnyOf(this.any);
  final List<Condition> any;

  @override
  Set<String> get reads => {for (final c in any) ...c.reads};
}

// --- Triggers -----------------------------------------------------------------

/// At most once per interval, per key (SPEC §13.2).
final class Throttle {
  const Throttle(this.every, {this.per});

  factory Throttle.parse(Object? v, String what) {
    final m = _map(v, what);
    return Throttle(
      parseDuration(m['every'], '$what.every'),
      per: _keyPath(m['per'], '$what.per'),
    );
  }

  final Duration every;

  /// A path into the trigger's data; null — one budget for all.
  final String? per;
}

String? _keyPath(Object? v, String what) {
  if (v == null) return null;
  final s = _str(v, what);
  return s.startsWith(r'$trigger.') ? s.substring(9) : s;
}

/// Why a reaction runs (SPEC §13.2).
sealed class Trigger {
  const Trigger({this.throttles = const [], this.once = false});

  final List<Throttle> throttles;
  final bool once;

  static Trigger parse(Object? v, String what) {
    final m = _map(v, what);
    final throttles = [
      for (final t in _list(m['throttle'])) Throttle.parse(t, '$what.throttle'),
    ];
    final once = m['once'] == true;
    if (m.containsKey('fact')) {
      return FactTrigger(
        _name(m['fact'], '$what.fact'),
        Filter.parse(m['where'], '$what.where'),
        throttles: throttles,
        once: once,
      );
    }
    if (m.containsKey('state')) {
      final which = [
        for (final k in const ['becomes', 'leaves', 'changes'])
          if (m.containsKey(k)) k,
      ];
      if (which.length > 1) _bad('$what: one of becomes, leaves, changes');
      final changes = m['changes'];
      final already = m['already'] == true;
      if (already &&
          !m.containsKey('becomes') &&
          !m.containsKey('leaves') &&
          !(changes is Map && changes.containsKey('to'))) {
        _bad('$what.already: with becomes, leaves or changes.to');
      }
      return StateTrigger(
        _name(m['state'], '$what.state'),
        key: m['key'] as String?,
        becomes: m.containsKey('becomes')
            ? ValueTest.parse(m['becomes'], '$what.becomes')
            : null,
        leaves: m.containsKey('leaves')
            ? ValueTest.parse(m['leaves'], '$what.leaves')
            : null,
        from: changes is Map && changes.containsKey('from')
            ? ValueTest.parse(changes['from'], '$what.changes.from')
            : null,
        to: changes is Map && changes.containsKey('to')
            ? ValueTest.parse(changes['to'], '$what.changes.to')
            : null,
        holdFor: m['for'] == null ? null : parseDuration(m['for'], '$what.for'),
        already: already,
        throttles: throttles,
        once: once,
      );
    }
    if (m.containsKey('every')) {
      final d = parseDuration(m['every'], '$what.every');
      if (d < const Duration(seconds: 1)) _bad('$what.every: at least 1s');
      return EveryTrigger(d, throttles: throttles, once: once);
    }
    if (m.containsKey('at')) {
      final at = RegExp(r'^(\d{1,2}):(\d{2})$')
          .firstMatch(_str(m['at'], '$what.at'));
      if (at == null) _bad('$what.at: expected HH:mm');
      final h = int.parse(at[1]!), min = int.parse(at[2]!);
      if (h > 23 || min > 59) _bad('$what.at: expected HH:mm');
      final days = [for (final d in _list(m['days'])) d as int];
      if (days.any((d) => d < 1 || d > 7)) _bad('$what.days: 1 (Mon) to 7');
      return AtTrigger(h, min, days.toSet(), throttles: throttles, once: once);
    }
    if (m.containsKey('manual')) {
      return ManualTrigger(
        m['manual'] is Map ? _map(m['manual'], '$what.manual') : const {},
        throttles: throttles,
        once: once,
      );
    }
    // An extension's: the engine finds which registered extension it is
    // by the keys.
    final raw = {
      for (final e in m.entries)
        if (e.key != 'throttle' && e.key != 'once') e.key: e.value,
    };
    if (raw.isEmpty) _bad('$what: no trigger');
    return ExtensionTrigger(raw, throttles: throttles, once: once);
  }
}

final class FactTrigger extends Trigger {
  const FactTrigger(this.fact, this.where, {super.throttles, super.once});

  final String fact;
  final Filter where;
}

final class StateTrigger extends Trigger {
  const StateTrigger(
    this.state, {
    this.key,
    this.becomes,
    this.leaves,
    this.from,
    this.to,
    this.holdFor,
    this.already = false,
    super.throttles,
    super.once,
  });

  final String state;
  final String? key;
  final ValueTest? becomes;
  final ValueTest? leaves;
  final ValueTest? from;
  final ValueTest? to;

  /// And stays so this long.
  final Duration? holdFor;

  /// Fires too for what already holds: when the link starts, and when a
  /// value comes where there was none. Without it, only a change fires it.
  final bool already;

  /// Whether a change from [previous] to [value] fires it.
  bool fires(Object? previous, Object? value) {
    if (becomes case final t?) return t.matches(value) && !t.matches(previous);
    if (leaves case final t?) return t.matches(previous) && !t.matches(value);
    if (jsonEquals(previous, value)) return false;
    return (from?.matches(previous) ?? true) && (to?.matches(value) ?? true);
  }

  /// Whether [value] still holds the condition it fired on, for [holdFor].
  bool holds(Object? value) {
    if (becomes case final t?) return t.matches(value);
    if (leaves case final t?) return !t.matches(value);
    return to?.matches(value) ?? true;
  }
}

final class EveryTrigger extends Trigger {
  const EveryTrigger(this.interval, {super.throttles, super.once});
  final Duration interval;
}

/// At a local time of day, on [days] (1 = Monday; empty — every day).
final class AtTrigger extends Trigger {
  const AtTrigger(
    this.hour,
    this.minute,
    this.days, {
    super.throttles,
    super.once,
  });
  final int hour;
  final int minute;
  final Set<int> days;

  /// The first such moment after [now], local time.
  DateTime nextAfter(DateTime now) {
    final local = now.toLocal();
    for (var d = 0; d <= 7; d++) {
      final day = DateTime(
        local.year,
        local.month,
        local.day + d,
        hour,
        minute,
      );
      if (!day.isAfter(local)) continue;
      if (days.isEmpty || days.contains(day.weekday)) return day;
    }
    return DateTime(local.year, local.month, local.day + 8, hour, minute);
  }
}

/// Pressed through `links.press`; [look] is the host's (a button's label).
final class ManualTrigger extends Trigger {
  const ManualTrigger(this.look, {super.throttles, super.once});
  final Map<String, Object?> look;
}

/// A trigger of the host's, resolved by a registered extension whose name
/// is one of the keys of [raw].
final class ExtensionTrigger extends Trigger {
  const ExtensionTrigger(this.raw, {super.throttles, super.once});
  final Map<String, Object?> raw;
}

// --- Steps --------------------------------------------------------------------

/// What a run does (SPEC §13.4).
sealed class Step {
  const Step();

  static Step parse(Object? v, String what) {
    final m = _map(v, what);
    if (m.containsKey('call')) {
      return CallStep(
        _name(m['call'], '$what.call'),
        m['params'] == null ? const {} : _map(m['params'], '$what.params'),
        orContinue: m['orContinue'] == true,
      );
    }
    if (m.containsKey('flip')) {
      return FlipStep(
        _name(m['flip'], '$what.flip'),
        key: m['key'] as String?,
        orContinue: m['orContinue'] == true,
      );
    }
    if (m.containsKey('wait')) {
      return WaitStep(parseDuration(m['wait'], '$what.wait'));
    }
    if (m.containsKey('waitUntil')) {
      return WaitUntilStep(
        _Until.parse(m['waitUntil'], '$what.waitUntil'),
        parseDuration(m['timeout'], '$what.timeout'),
        orContinue: m['orContinue'] == true,
      );
    }
    if (m.containsKey('temporarily')) {
      final t = _map(m['temporarily'], '$what.temporarily');
      final hasFor = t.containsKey('for'), hasUntil = t.containsKey('until');
      if (hasFor == hasUntil) _bad('$what.temporarily: for or until');
      final steps = _list(t['do']);
      return TemporarilyStep(
        holdFor: hasFor
            ? parseDuration(t['for'], '$what.temporarily.for')
            : null,
        until: hasUntil
            ? _Until.parse(t['until'], '$what.temporarily.until')
            : null,
        steps: [
          for (var i = 0; i < steps.length; i++)
            switch (Step.parse(steps[i], '$what.temporarily.do.$i')) {
              final CallStep c => c,
              _ => _bad('$what.temporarily.do.$i: only calls'),
            },
        ],
      );
    }
    _bad('$what: not a step');
  }
}

final class CallStep extends Step {
  const CallStep(this.command, this.params, {this.orContinue = false});

  final String command;

  /// Values, `$trigger.<path>` and `$state.<name>[<key>]` references and
  /// `{path}` templates.
  final Map<String, Object?> params;

  /// A refusal does not stop the run.
  final bool orContinue;
}

final class FlipStep extends Step {
  const FlipStep(this.state, {this.key, this.orContinue = false});
  final String state;
  final String? key;
  final bool orContinue;
}

final class WaitStep extends Step {
  const WaitStep(this.duration);
  final Duration duration;
}

/// What a wait waits for: a fact or a condition.
final class Until {
  const Until({this.fact, this.condition});
  final FactTrigger? fact;
  final Condition? condition;
}

abstract final class _Until {
  static Until parse(Object? v, String what) {
    final m = _map(v, what);
    if (m.containsKey('fact')) {
      final t = Trigger.parse(m, what);
      return Until(fact: t as FactTrigger);
    }
    return Until(condition: Condition.parse(m['while'] ?? m, what));
  }
}

final class WaitUntilStep extends Step {
  const WaitUntilStep(this.until, this.timeout, {this.orContinue = false});
  final Until until;
  final Duration timeout;
  final bool orContinue;
}

final class TemporarilyStep extends Step {
  const TemporarilyStep({this.holdFor, this.until, required this.steps});
  final Duration? holdFor;
  final Until? until;
  final List<CallStep> steps;
}

// --- Links --------------------------------------------------------------------

/// How a reaction behaves when it fires while running (SPEC §13.5).
enum RunMode { single, restart, queue }

/// One link: an own word or one of the four relations.
sealed class Link {
  const Link(this.id, this.json, {required this.enabled, required this.name});

  /// Parses one definition; its keys say which kind it is.
  factory Link.parse(Object? v) {
    final m = _map(v, 'link');
    final id = _str(m['id'], 'id');
    final what = 'link $id';
    final enabled = m['enabled'] != false;
    final name = m['name'] as String? ?? id;
    final json = freezeJson(m) as Map<String, Object?>;
    if (m.containsKey('command')) {
      return OwnCommand(
        id,
        json,
        enabled: enabled,
        name: name,
        command: _ownName(m['command'], '$what.command'),
        params: ObjectType({
          for (final e in _map(m['params'] ?? const {}, '$what.params').entries)
            e.key: _field(e.value, '$what.params.${e.key}'),
        }),
        callers: m['callers'] == null ? null : Callers.fromJson(m['callers']),
        steps: _steps(m['do'], what),
      );
    }
    if (m.containsKey('state') && !m.containsKey('when')) {
      final values = m['values'];
      final ValueType<Object?> type = values == null
          ? const BoolType()
          : EnumType([for (final x in values as List) x as String]);
      final def =
          m['default'] ?? (values == null ? false : (values as List).first);
      return OwnState(
        id,
        json,
        enabled: enabled,
        name: name,
        state: _ownName(m['state'], '$what.state'),
        type: type,
        defaultValue: def,
      );
    }
    if (m.containsKey('when')) {
      final mode = RunMode.values.byName(m['mode'] as String? ?? 'single');
      return Reaction(
        id,
        json,
        enabled: enabled,
        name: name,
        triggers: [
          for (final (i, t) in _list(m['when']).indexed)
            Trigger.parse(t, '$what.when.$i'),
        ],
        only: m['only'] == null
            ? null
            : Condition.parse(m['only'], '$what.only'),
        mode: mode,
        queueLimit: m['queueLimit'] as int? ?? 10,
        steps: _steps(m['do'], what),
      );
    }
    if (m.containsKey('hold')) {
      final anchor = m['anchor'] == null
          ? null
          : _map(m['anchor'], '$what.anchor');
      if ((anchor == null) == (m['while'] == null)) {
        _bad('$what: a binding has while or an anchor');
      }
      return Binding(
        id,
        json,
        enabled: enabled,
        name: name,
        condition: m['while'] == null
            ? null
            : Condition.parse(m['while'], '$what.while'),
        anchor: anchor == null
            ? null
            : (
                kind: anchor.keys.single,
                entity: _str(anchor.values.single, '$what.anchor'),
              ),
        holds: [
          for (final (i, s) in _list(m['hold']).indexed)
            switch (Step.parse(s, '$what.hold.$i')) {
              final CallStep c => c,
              _ => _bad('$what.hold.$i: only calls'),
            },
        ],
        priority: m['priority'] as int? ?? 0,
      );
    }
    if (m.containsKey('deny')) {
      final d = _map(m['deny'], '$what.deny');
      final applies = m['callers'] ?? d['callers'];
      return Constraint(
        id,
        json,
        enabled: enabled,
        name: name,
        command: d['command'] == null
            ? null
            : _name(d['command'], '$what.deny.command'),
        where: Filter.parse(d['where'], '$what.deny.where'),
        namespace: d['namespace'] == null
            ? null
            : _name(d['namespace'], '$what.deny.namespace'),
        appliesTo: applies == null || applies == 'any'
            ? null
            : {for (final c in _list(applies)) _str(c, '$what.callers')},
        condition: m['while'] == null
            ? null
            : Condition.parse(m['while'], '$what.while'),
        reason: _str(m['reason'] ?? name, '$what.reason'),
        overridable: m['overridable'] != false,
      );
    }
    if (m.containsKey('before')) {
      final b = _map(m['before'], '$what.before');
      return Interception(
        id,
        json,
        enabled: enabled,
        name: name,
        command: _name(b['command'], '$what.before.command'),
        steps: _steps(m['do'], what),
        priority: m['priority'] as int? ?? 0,
        timeout: parseDuration(m['timeout'], '$what.timeout'),
      );
    }
    _bad('$what: not a link');
  }

  final String id;

  /// The definition as given.
  final Map<String, Object?> json;
  final bool enabled;
  final String name;
}

/// A field of an own command's params: a type with `optional` and
/// `default` beside it (`{type: int, min: 5, default: 30}`), or a field as
/// [Field.toJson] gives it.
Field _field(Object? v, String what) {
  final m = _map(v, what);
  try {
    if (m['type'] is String) {
      final type = ValueType.fromJson({
        for (final e in m.entries)
          if (e.key != 'optional' && e.key != 'default') e.key: e.value,
      });
      return Field(
        type,
        optional: m['optional'] == true,
        defaultValue: m['default'],
      );
    }
    return Field.fromJson(m);
  } on FormatException catch (e) {
    _bad('$what: ${e.message}');
  } on TypeError {
    _bad('$what: not a type');
  }
}

String _ownName(Object? v, String what) {
  final s = _name(v, what);
  return s.startsWith(LinkWords.ownPrefix) ? s : '${LinkWords.ownPrefix}$s';
}

List<Step> _steps(Object? v, String what) => [
  for (final (i, s) in _list(v).indexed) Step.parse(s, '$what.do.$i'),
];

/// A command of the user's own (SPEC §13.1).
final class OwnCommand extends Link {
  const OwnCommand(
    super.id,
    super.json, {
    required super.enabled,
    required super.name,
    required this.command,
    required this.params,
    required this.callers,
    required this.steps,
  });

  final String command;
  final ObjectType params;

  /// Null — every kind but `system`.
  final Callers? callers;
  final List<Step> steps;
}

/// A flag or a mode of the user's own (SPEC §13.1).
final class OwnState extends Link {
  const OwnState(
    super.id,
    super.json, {
    required super.enabled,
    required super.name,
    required this.state,
    required this.type,
    required this.defaultValue,
  });

  final String state;
  final ValueType<Object?> type;
  final Object? defaultValue;

  String get setter => '$state.set';
}

final class Reaction extends Link {
  const Reaction(
    super.id,
    super.json, {
    required super.enabled,
    required super.name,
    required this.triggers,
    required this.only,
    required this.mode,
    required this.queueLimit,
    required this.steps,
  });

  final List<Trigger> triggers;
  final Condition? only;
  final RunMode mode;
  final int queueLimit;
  final List<Step> steps;
}

final class Binding extends Link {
  const Binding(
    super.id,
    super.json, {
    required super.enabled,
    required super.name,
    required this.condition,
    required this.anchor,
    required this.holds,
    required this.priority,
  });

  final Condition? condition;

  /// An anchor kind and the entity, instead of [condition].
  final ({String kind, String entity})? anchor;
  final List<CallStep> holds;
  final int priority;
}

final class Constraint extends Link {
  const Constraint(
    super.id,
    super.json, {
    required super.enabled,
    required super.name,
    required this.command,
    required this.where,
    required this.namespace,
    required this.appliesTo,
    required this.condition,
    required this.reason,
    required this.overridable,
  });

  /// One command, with [where] on its params.
  final String? command;
  final Filter where;

  /// Every command whose name starts with `namespace.`.
  final String? namespace;

  /// Selectors of the principals it applies to; null — everyone.
  final Set<String>? appliesTo;
  final Condition? condition;
  final String reason;
  final bool overridable;

  bool appliesToPrincipal(Principal p) =>
      appliesTo == null ||
      appliesTo!.contains(p.kind) ||
      appliesTo!.contains(p.selector);

  bool targets(String commandName, Map<String, Object?> params) {
    if (command != null) {
      return command == commandName && where.matches(params);
    }
    if (namespace != null) return commandName.startsWith('$namespace.');
    return true;
  }
}

final class Interception extends Link {
  const Interception(
    super.id,
    super.json, {
    required super.enabled,
    required super.name,
    required this.command,
    required this.steps,
    required this.priority,
    required this.timeout,
  });

  final String command;
  final List<Step> steps;
  final int priority;
  final Duration timeout;
}
