/// Links are data: parsed from JSON, kept as given. Nothing here knows the
/// registry; the engine reads and calls through its participant.
library;

import 'package:parlance/tools.dart' show jsonAt, jsonEquals;

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

/// Text, or nothing.
String? _maybeStr(Object? v, String what) => v == null ? null : _str(v, what);

final _namePattern = RegExp(r'^[a-z][a-z0-9_-]*(\.[a-z0-9][a-z0-9_-]*)*$');

/// A word's name: dotted, lower-case.
String _name(Object? v, String what) {
  final s = _str(v, what);
  if (!_namePattern.hasMatch(s)) {
    _bad('$what: $s is not a dotted lower-case name');
  }
  return s;
}

/// A duration in a link: milliseconds, or text like `500ms`, `15s`, `2m`,
/// `1h`.
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

// --- Tests on values ---------------------------------------------------------

/// A comparison: `is`, `not`, `in`, `<`, `<=`, `>`, `>=`.
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
      if (v.keys.single case final String key) {
        if (Op.of(key) case final op?) {
          final operand = v[key];
          if (op == Op.isIn && operand is! List) _bad('$what: in takes a list');
          if (op.index >= Op.lt.index && operand is! num) {
            _bad('$what: ${op.symbol} takes a number');
          }
          return ValueTest(op, operand);
        }
      }
    }
    return ValueTest(Op.isEqual, v);
  }

  final Op op;
  final Object? operand;

  bool matches(Object? value) => switch (op) {
    Op.isEqual => jsonEquals(value, operand),
    Op.not => !jsonEquals(value, operand),
    Op.isIn => (operand! as List).any((o) => jsonEquals(o, value)),
    Op.lt => value is num && value < (operand! as num),
    Op.le => value is num && value <= (operand! as num),
    Op.gt => value is num && value > (operand! as num),
    Op.ge => value is num && value >= (operand! as num),
  };

  @override
  String toString() => op == Op.isEqual ? '$operand' : '${op.symbol} $operand';
}

/// Tests on fields of a value, by path: all must hold.
final class Filter {
  const Filter(this.tests);

  factory Filter.parse(Object? v, String what) {
    if (v == null) return const Filter({});
    return Filter({
      for (final e in _map(v, what).entries)
        e.key: ValueTest.parse(e.value, '$what.${e.key}'),
    });
  }

  final Map<String, ValueTest> tests;

  bool matches(Object? value) =>
      tests.entries.every((e) => e.value.matches(jsonAt(value, e.key)));
}

// --- Conditions --------------------------------------------------------------

/// What must hold for a run to go: read on the participant's view as it is
/// when the trigger fires.
sealed class Condition {
  const Condition();

  /// A list means all; `{any: [...]}` at least one; else one test of a
  /// state: `{state, key?, is | not | in | < | <= | > | >=}`.
  static Condition parse(Object? v, String what) {
    if (v is List) {
      return AllOf([
        for (final (i, c) in v.indexed) Condition.parse(c, '$what.$i'),
      ]);
    }
    final m = _map(v, what);
    if (m.containsKey('any')) {
      return AnyOf([
        for (final (i, c) in _list(m['any']).indexed)
          Condition.parse(c, '$what.any.$i'),
      ]);
    }
    final ops = [
      for (final k in m.keys)
        if (Op.of(k) != null) k,
    ];
    if (ops.length != 1) _bad('$what: one of is, not, in, <, <=, >, >=');
    return StateIs(
      _name(m['state'], '$what.state'),
      _maybeStr(m['key'], '$what.key'),
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

  @override
  String toString() => '$state${key == null ? '' : '[$key]'} is $test';
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

// --- Triggers ----------------------------------------------------------------

/// At most once per [every], per value at [per] in the trigger's data.
final class Throttle {
  const Throttle(this.every, {this.per});

  factory Throttle.parse(Object? v, String what) {
    final m = _map(v, what);
    final per = m['per'];
    return Throttle(
      parseDuration(m['every'], '$what.every'),
      per: per == null
          ? null
          : _str(per, '$what.per').replaceFirst(r'$trigger.', ''),
    );
  }

  final Duration every;

  /// A path into the trigger's data; null: one budget for all.
  final String? per;
}

/// Why a link runs.
sealed class Trigger {
  const Trigger({this.throttles = const []});

  final List<Throttle> throttles;

  static Trigger parse(Object? v, String what) {
    final m = _map(v, what);
    final throttles = [
      for (final t in _list(m['throttle'])) Throttle.parse(t, '$what.throttle'),
    ];
    if (m.containsKey('fact')) {
      return FactTrigger(
        _name(m['fact'], '$what.fact'),
        Filter.parse(m['where'], '$what.where'),
        throttles: throttles,
      );
    }
    if (m.containsKey('state')) {
      final which = [
        for (final k in const ['becomes', 'leaves', 'changes'])
          if (m.containsKey(k)) k,
      ];
      if (which.length > 1) _bad('$what: one of becomes, leaves, changes');
      final changes = m['changes'];
      if (changes != null && changes is! Map) {
        _bad('$what.changes: an object, {from?, to?}');
      }
      final already = m['already'] == true;
      if (already && !m.containsKey('becomes') && !m.containsKey('leaves')) {
        _bad('$what.already: with becomes or leaves');
      }
      return StateTrigger(
        _name(m['state'], '$what.state'),
        key: _maybeStr(m['key'], '$what.key'),
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
      );
    }
    if (m.containsKey('every')) {
      final d = parseDuration(m['every'], '$what.every');
      if (d < const Duration(seconds: 1)) _bad('$what.every: at least 1s');
      return EveryTrigger(d, throttles: throttles);
    }
    if (m.containsKey('button')) {
      return ButtonTrigger.parse(m['button'], '$what.button', throttles);
    }
    // A trigger of the owner's: an extension registered by one of the
    // keys finds it.
    final raw = {
      for (final e in m.entries)
        if (e.key != 'throttle') e.key: e.value,
    };
    if (raw.isEmpty) _bad('$what: no trigger');
    return ExtensionTrigger(raw, throttles: throttles);
  }
}

/// A fact said, its payload as [where] says.
final class FactTrigger extends Trigger {
  const FactTrigger(this.fact, this.where, {super.throttles});

  final String fact;
  final Filter where;
}

/// A change of a state (of [key]): it [becomes] a value, [leaves] one, or
/// [changes] from one to another (either may be left out). A value that
/// comes where there was none is no change: the owner's first value is
/// not news. With [already], a value that already holds fires it too: when
/// the link starts, and when the value comes.
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
  });

  final String state;
  final String? key;
  final ValueTest? becomes;
  final ValueTest? leaves;
  final ValueTest? from;
  final ValueTest? to;

  /// And stays so this long.
  final Duration? holdFor;
  final bool already;

  /// Whether a change from [previous] to [value] fires it.
  bool fires(Object? previous, Object? value) {
    if (becomes case final t?) return t.matches(value) && !t.matches(previous);
    if (leaves case final t?) return t.matches(previous) && !t.matches(value);
    if (jsonEquals(previous, value)) return false;
    return (from?.matches(previous) ?? true) && (to?.matches(value) ?? true);
  }

  /// Whether [value] is what it fires on: what [already] and [holdFor]
  /// look at.
  bool holds(Object? value) {
    if (becomes case final t?) return t.matches(value);
    if (leaves case final t?) return !t.matches(value);
    return to?.matches(value) ?? true;
  }
}

/// Every [interval], from when the link starts.
final class EveryTrigger extends Trigger {
  const EveryTrigger(this.interval, {super.throttles});
  final Duration interval;
}

/// A button: pressed on a desk, a phone or a Stream Deck, through the
/// owner's press command. How it looks is the owner's to draw: [look]
/// holds `label`, `icon`, `group`, `groupLabel`, `choice`, `tooltip`,
/// `litLabel`; [lit] says when it is lit.
final class ButtonTrigger extends Trigger {
  const ButtonTrigger(this.look, {this.lit, super.throttles});

  factory ButtonTrigger.parse(
    Object? v,
    String what,
    List<Throttle> throttles,
  ) {
    final m = _map(v, what);
    _str(m['label'], '$what.label');
    return ButtonTrigger(
      {
        for (final e in m.entries)
          if (e.key != 'lit') e.key: e.value,
      },
      lit: m['lit'] == null ? null : Condition.parse(m['lit'], '$what.lit'),
      throttles: throttles,
    );
  }

  final Map<String, Object?> look;
  final Condition? lit;
}

/// A trigger of the owner's, resolved by a registered extension named by
/// one of the keys of [raw].
final class ExtensionTrigger extends Trigger {
  const ExtensionTrigger(this.raw, {super.throttles});
  final Map<String, Object?> raw;
}

// --- Steps -------------------------------------------------------------------

/// What a run does.
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
    if (m.containsKey('wait')) {
      return WaitStep(parseDuration(m['wait'], '$what.wait'));
    }
    _bad('$what: a step is {call, params?} or {wait}');
  }
}

/// Calls [command] with [params]: values as given, a text that is all
/// `$trigger.<path>` the value at that path in the trigger's data.
final class CallStep extends Step {
  const CallStep(this.command, this.params, {this.orContinue = false});

  final String command;
  final Map<String, Object?> params;

  /// A refusal does not stop the run.
  final bool orContinue;
}

final class WaitStep extends Step {
  const WaitStep(this.duration);
  final Duration duration;
}

// --- Links -------------------------------------------------------------------

/// What a link does when it fires while it runs: [single] lets the new
/// one go, [queue] runs it after (up to its queue's limit).
enum RunMode { single, queue }

/// One link: when one of [triggers] fires, and [only] holds, it does
/// [steps], in order.
final class Link {
  const Link({
    required this.id,
    required this.name,
    required this.triggers,
    required this.steps,
    this.only,
    this.mode = RunMode.single,
    this.queueLimit = 10,
    this.enabled = true,
    this.json = const {},
  });

  factory Link.parse(Object? v) {
    final m = _map(v, 'link');
    final id = _str(m['id'], 'id');
    final what = 'link $id';
    if (!m.containsKey('when')) _bad('$what: when it runs (when)');
    final mode = switch (m['mode']) {
      null || 'single' => RunMode.single,
      'queue' => RunMode.queue,
      final x => _bad('$what.mode: single or queue, not $x'),
    };
    final triggers = [
      for (final (i, t) in _list(m['when']).indexed)
        Trigger.parse(t, '$what.when.$i'),
    ];
    if (triggers.isEmpty) _bad('$what.when: at least one trigger');
    return Link(
      id: id,
      name: _maybeStr(m['name'], '$what.name') ?? id,
      enabled: m['enabled'] != false,
      triggers: triggers,
      only: m['only'] == null ? null : Condition.parse(m['only'], '$what.only'),
      mode: mode,
      queueLimit: switch (m['queueLimit']) {
        null => 10,
        final int n when n > 0 => n,
        final x => _bad('$what.queueLimit: a count from 1, not $x'),
      },
      steps: [
        for (final (i, s) in _list(m['do']).indexed)
          Step.parse(s, '$what.do.$i'),
      ],
      json: m,
    );
  }

  final String id;
  final String name;
  final bool enabled;
  final List<Trigger> triggers;
  final Condition? only;
  final RunMode mode;
  final int queueLimit;
  final List<Step> steps;

  /// The definition as given.
  final Map<String, Object?> json;

  /// Its button, when one of its triggers is one.
  ButtonTrigger? get button {
    for (final t in triggers) {
      if (t is ButtonTrigger) return t;
    }
    return null;
  }
}
