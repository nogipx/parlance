import 'cause.dart';
import 'ids.dart';
import 'json.dart';
import 'types.dart';

/// One entity of a kind, as `describe` lists it.
final class EntityRef {
  const EntityRef(this.id, [String? label, this.meta = const {}])
    : label = label ?? id;

  final String id;
  final String label;

  /// What else the host tells of it, as JSON: what an editor or an agent
  /// needs to choose it or use it (the type of the value it takes...).
  final Map<String, Object?> meta;

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    if (meta.isNotEmpty) 'meta': meta,
  };
}

/// A kind of entity the host has: rooms, devices, documents (SPEC §3).
final class EntityKind {
  EntityKind(this.name, {required this.list, this.meta = const {}}) {
    checkName(name, 'kind');
  }

  final String name;

  /// The entities there are now.
  final Iterable<EntityRef> Function() list;

  final Map<String, Object?> meta;

  bool contains(String id) => list().any((e) => e.id == id);

  Map<String, Object?> toJson() => {
    'name': name,
    'entities': [for (final e in list()) e.toJson()],
    if (meta.isNotEmpty) 'meta': meta,
  };
}

/// What a principal may do with a command.
enum Access {
  allow,

  /// Allowed; editors warn the author who else can now do it.
  warn,
  deny,
}

/// Who may call a command: selectors (`user`, `plugin/hydra`, `*` for
/// anyone) to access; the most specific selector wins, an unmatched
/// principal is denied. A selector names the parts of what it names too
/// (`plugin/hydra` names `plugin/hydra@ui`), so the nearest one wins:
/// the part's own, then its whole, then its kind.
final class Callers {
  const Callers(this.rules);

  factory Callers.fromJson(Object? json) => Callers({
    for (final e in (json as Map).entries)
      e.key as String: Access.values.byName(e.value as String),
  });

  /// Every principal kind in [kinds] allowed.
  Callers.only(Iterable<String> kinds)
    : rules = {for (final k in kinds) k: Access.allow};

  final Map<String, Access> rules;

  /// Throws when a selector is not one (SPEC §4): `*` or
  /// `kind[/id][@owner]` (`plugin`, `plugin/hydra`, `studio@screen`). One
  /// that could name no one would match nobody, quietly.
  void check() {
    for (final s in rules.keys) {
      if (s == '*') continue;
      try {
        Principal.parse(s);
      } on ArgumentError catch (e) {
        throw ArgumentError.value(s, 'selector', '${e.message}');
      }
    }
  }

  Access accessOf(Principal p) {
    for (Principal? q = p; q != null; q = q.parent) {
      if (rules[q.selector] case final a?) return a;
    }
    return rules['*'] ?? Access.deny;
  }

  bool allows(Principal p) => accessOf(p) != Access.deny;

  Map<String, Object?> toJson() => {
    for (final e in rules.entries) e.key: e.value.name,
  };
}

/// What everything in the catalog has.
sealed class Descriptor {
  Descriptor(this.name, this.meta) {
    checkWordName(name);
    if (!isJsonValue(meta)) throw ArgumentError.value(meta, 'meta');
  }

  final String name;

  /// The host's own notes (labels, units, icons); the registry never reads
  /// them.
  final Map<String, Object?> meta;

  Map<String, Object?> toJson();

  static Descriptor fromJson(Object? json) {
    final m = json as Map;
    return switch (m['is']) {
      'state' => StateDescriptor.fromJson(m),
      'command' => CommandDescriptor.fromJson(m),
      'query' => QueryDescriptor.fromJson(m),
      'fact' => FactDescriptor.fromJson(m),
      final x => throw FormatException('unknown descriptor $x'),
    };
  }
}

/// A value there is now; one writer (SPEC §6.1).
final class StateDescriptor extends Descriptor {
  StateDescriptor(
    String name, {
    required this.type,
    this.key,
    this.readers,
    Map<String, Object?> meta = const {},
  }) : super(name, meta) {
    readers?.check();
  }

  factory StateDescriptor.fromJson(Map<Object?, Object?> m) => StateDescriptor(
    m['name'] as String,
    type: ValueType.fromJson(m['type']),
    key: m['key'] as String?,
    readers: m['readers'] == null ? null : Callers.fromJson(m['readers']),
    meta: (m['meta'] as Map?)?.cast<String, Object?>() ?? const {},
  );

  final ValueType<Object?> type;

  /// The entity kind of its keys, when it holds one value per entity.
  final String? key;

  /// Who may read its values over remote and MCP, as callers
  /// name who may call a command (SPEC §6.1); null for everyone. Its
  /// descriptor is in the catalog for all. Code in the registry's own
  /// process reads it anyway.
  final Callers? readers;

  bool get keyed => key != null;

  @override
  Map<String, Object?> toJson() => {
    'is': 'state',
    'name': name,
    'type': type.toJson(),
    'key': ?key,
    'readers': ?readers?.toJson(),
    if (meta.isNotEmpty) 'meta': meta,
  };
}

/// What is called and answered by one handler (SPEC §9): a command or a
/// query. Both go through the same stages; what tells them apart is in
/// their own types.
sealed class CallableDescriptor extends Descriptor {
  CallableDescriptor(
    super.name,
    super.meta, {
    required this.params,
    required this.returns,
    required this.callers,
    required this.deadline,
  }) {
    callers.check();
    if (deadline <= Duration.zero) {
      throw ArgumentError.value(deadline, 'deadline', 'a while, not none');
    }
  }

  final ObjectType params;

  /// The type of what a call answers; null: it answers nothing.
  final ValueType<Object?>? returns;

  /// Who may call it, or ask it.
  final Callers callers;

  /// How long the handler may take.
  final Duration deadline;
}

/// A request one handler serves (SPEC §6.2): it may change something.
final class CommandDescriptor extends CallableDescriptor {
  CommandDescriptor(
    String name, {
    ObjectType params = const ObjectType({}),
    super.returns,
    required super.callers,
    super.deadline = const Duration(seconds: 30),
    Map<String, Object?> meta = const {},
  }) : super(name, meta, params: params);

  factory CommandDescriptor.fromJson(Map<Object?, Object?> m) =>
      CommandDescriptor(
        m['name'] as String,
        params: ValueType.fromJson(m['params']) as ObjectType,
        returns: m['returns'] == null ? null : ValueType.fromJson(m['returns']),
        callers: Callers.fromJson(m['callers']),
        deadline: Duration(milliseconds: m['deadline'] as int? ?? 30000),
        meta: (m['meta'] as Map?)?.cast<String, Object?>() ?? const {},
      );

  @override
  Map<String, Object?> toJson() => {
    'is': 'command',
    'name': name,
    'params': params.toJson(),
    if (returns != null) 'returns': returns!.toJson(),
    'callers': callers.toJson(),
    'deadline': deadline.inMilliseconds,
    if (meta.isNotEmpty) 'meta': meta,
  };
}

/// A question one handler answers (SPEC §6.6): it changes nothing.
/// Asked again it runs again, and no call record keeps it.
final class QueryDescriptor extends CallableDescriptor {
  QueryDescriptor(
    String name, {
    ObjectType params = const ObjectType({}),
    required ValueType<Object?> returns,
    required Callers askers,
    Duration deadline = const Duration(seconds: 30),
    Map<String, Object?> meta = const {},
  }) : super(
         name,
         meta,
         params: params,
         returns: returns,
         callers: askers,
         deadline: deadline,
       );

  factory QueryDescriptor.fromJson(Map<Object?, Object?> m) => QueryDescriptor(
    m['name'] as String,
    params: ValueType.fromJson(m['params']) as ObjectType,
    returns: ValueType.fromJson(m['returns']),
    askers: Callers.fromJson(m['askers']),
    deadline: Duration(milliseconds: m['deadline'] as int? ?? 30000),
    meta: (m['meta'] as Map?)?.cast<String, Object?>() ?? const {},
  );

  /// Who may ask it.
  Callers get askers => callers;

  /// What it answers, always.
  ValueType<Object?> get answers => returns!;

  @override
  Map<String, Object?> toJson() => {
    'is': 'query',
    'name': name,
    'params': params.toJson(),
    'returns': answers.toJson(),
    'askers': askers.toJson(),
    'deadline': deadline.inMilliseconds,
    if (meta.isNotEmpty) 'meta': meta,
  };
}

/// Something that happened and is not a state (SPEC §6.3).
final class FactDescriptor extends Descriptor {
  FactDescriptor(
    String name, {
    required this.type,
    this.open = false,
    this.readers,
    Map<String, Object?> meta = const {},
  }) : super(name, meta) {
    readers?.check();
  }

  factory FactDescriptor.fromJson(Map<Object?, Object?> m) => FactDescriptor(
    m['name'] as String,
    type: ValueType.fromJson(m['type']),
    open: m['open'] == true,
    readers: m['readers'] == null ? null : Callers.fromJson(m['readers']),
    meta: (m['meta'] as Map?)?.cast<String, Object?>() ?? const {},
  );

  final ValueType<Object?> type;

  /// More producers than the definer may emit it.
  final bool open;

  /// Who may hear it over remote and MCP, as a state's
  /// [StateDescriptor.readers]; null for everyone.
  final Callers? readers;

  @override
  Map<String, Object?> toJson() => {
    'is': 'fact',
    'name': name,
    'type': type.toJson(),
    if (open) 'open': true,
    'readers': ?readers?.toJson(),
    if (meta.isNotEmpty) 'meta': meta,
  };
}
