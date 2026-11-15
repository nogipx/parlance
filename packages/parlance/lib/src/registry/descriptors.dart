import 'address.dart';
import 'cause.dart';
import 'ids.dart';
import 'json.dart';
import 'types.dart';

/// What a principal may do with a command.
enum Access {
  /// Allowed, nothing said.
  allow,

  /// Allowed; actual interactions emit a diagnostic for the developer.
  warn,

  /// Not allowed.
  deny,
}

/// Who may call a command: selectors (`user`, `module/visit`, `*` for
/// anyone) to access; the most specific selector wins, an unmatched
/// principal is denied. A selector names the owners of what it names too
/// (`module/visit` names `module/visit@visit`), so the nearest one wins:
/// the owner's own, then its whole, then its kind.
final class Callers {
  /// Const constructor; [rules] maps a selector to its access.
  const Callers(this.rules);

  /// [json] as callers; an access a newer parlance has is
  /// [Access.deny], the least it may mean.
  factory Callers.fromJson(Object? json) => Callers({
    for (final e in (json as Map).entries)
      // An access of a newer parlance (SPEC §14) is denied: the least it
      // may mean.
      e.key as String: Access.values.asNameMap()[e.value] ?? Access.deny,
  });

  /// Anyone may.
  static const anyone = Callers({'*': Access.allow});

  /// Every principal kind in [kinds] allowed.
  Callers.only(Iterable<String> kinds)
    : rules = {for (final k in kinds) k: Access.allow};

  /// The selectors and their access; the most specific wins.
  final Map<String, Access> rules;

  /// Throws when a selector is not one (SPEC §4): `*` or
  /// `kind[/id][@owner]` (`module`, `module/visit`, `home@house`). One
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

  /// The access of [p]: its own selector's, the nearest one's up,
  /// else `*`.
  Access accessOf(Principal p) {
    for (Principal? q = p; q != null; q = q.parent) {
      if (rules[q.selector] case final a?) return a;
    }
    return rules['*'] ?? Access.deny;
  }

  /// Whether [p] may: its access is not [Access.deny].
  bool allows(Principal p) => accessOf(p) != Access.deny;

  /// Its JSON.
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

  /// The word: `<vocabulary>.<name>`.
  final String name;

  /// The host's own notes (labels, units, icons); the registry never reads
  /// them.
  final Map<String, Object?> meta;

  /// Its JSON.
  Map<String, Object?> toJson();

  /// [json] as a descriptor; an unknown `is` is a
  /// [FormatException].
  static Descriptor fromJson(Object? json) {
    final m = json as Map;
    return switch (m['is']) {
      'state' => StateDescriptor.fromJson(m),
      'command' => CommandDescriptor.fromJson(m),
      'query' => QueryDescriptor.fromJson(m),
      'fact' => FactDescriptor.fromJson(m),
      'serverStream' ||
      'clientStream' ||
      'bidiStream' => DataStreamDescriptor.fromJson(m.cast<String, Object?>()),
      final x => throw FormatException('unknown descriptor $x'),
    };
  }
}

/// A value there is now; one writer (SPEC §6.1).
final class StateDescriptor extends Descriptor {
  /// One of [name]: its values are [type], one per [key] identifier
  /// when keyed; [readers] who may read.
  StateDescriptor(
    String name, {
    required this.type,
    this.key,
    this.readers,
    Map<String, Object?> meta = const {},
  }) : super(name, meta) {
    readers?.check();
  }

  /// [json] as a state's descriptor.
  factory StateDescriptor.fromJson(Map<Object?, Object?> m) => StateDescriptor(
    m['name'] as String,
    type: ValueType.fromJson(m['type']),
    key: m['key'] as String?,
    readers: m['readers'] == null ? null : Callers.fromJson(m['readers']),
    meta: (m['meta'] as Map?)?.cast<String, Object?>() ?? const {},
  );

  /// What its values must pass.
  final ValueType<Object?> type;

  /// The name of the key parameter; null for an unkeyed state.
  final String? key;

  /// Who may read its values, as callers name who may call a command
  /// (SPEC §6.1); null for everyone. Its descriptor is in the catalog
  /// for all. Every read is held to it — over remote and MCP, and in
  /// the registry's own process as far as the code reads through a
  /// participant or a view; only the registry's own tools, on the raw
  /// registry, read anyway.
  final Callers? readers;

  /// Whether it holds one value per [key] identifier.
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

  /// What a call's params must pass.
  final RecordType params;

  /// The type of what a call answers; null: it answers nothing.
  final ValueType<Object?>? returns;

  /// Who may call it, or ask it.
  final Callers callers;

  /// How long the handler may take.
  final Duration deadline;
}

/// How long a handler may take when its word does not say (SPEC §9).
const defaultDeadline = Duration(seconds: 30);

/// A request one handler serves (SPEC §6.2): it may change something.
final class CommandDescriptor extends CallableDescriptor {
  /// One of [name]: [callers] who may call it; [params] in,
  /// [returns] out, as the word says.
  CommandDescriptor(
    String name, {
    RecordType params = const RecordType({}),
    super.returns,
    required super.callers,
    super.deadline = defaultDeadline,
    Map<String, Object?> meta = const {},
  }) : super(name, meta, params: params);

  /// [json] as a command's descriptor.
  factory CommandDescriptor.fromJson(Map<Object?, Object?> m) =>
      CommandDescriptor(
        m['name'] as String,
        params: RecordType.fromJson(m['params']),
        returns: m['returns'] == null ? null : ValueType.fromJson(m['returns']),
        callers: Callers.fromJson(m['callers']),
        deadline: Duration(
          milliseconds: m['deadline'] as int? ?? defaultDeadline.inMilliseconds,
        ),
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
  /// One of [name]: [askers] who may ask it; [params] in,
  /// [returns] out.
  QueryDescriptor(
    String name, {
    RecordType params = const RecordType({}),
    required ValueType<Object?> returns,
    required Callers askers,
    Duration deadline = defaultDeadline,
    Map<String, Object?> meta = const {},
  }) : super(
         name,
         meta,
         params: params,
         returns: returns,
         callers: askers,
         deadline: deadline,
       );

  /// [json] as a query's descriptor.
  factory QueryDescriptor.fromJson(Map<Object?, Object?> m) => QueryDescriptor(
    m['name'] as String,
    params: RecordType.fromJson(m['params']),
    returns: ValueType.fromJson(m['returns']),
    askers: Callers.fromJson(m['askers']),
    deadline: Duration(
      milliseconds: m['deadline'] as int? ?? defaultDeadline.inMilliseconds,
    ),
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
  /// One of [name]: its payload is [type]; [readers] who may hear it.
  FactDescriptor(
    String name, {
    required this.type,
    this.readers,
    Map<String, Object?> meta = const {},
  }) : super(name, meta) {
    readers?.check();
  }

  /// [json] as a fact's descriptor.
  factory FactDescriptor.fromJson(Map<Object?, Object?> m) => FactDescriptor(
    m['name'] as String,
    type: ValueType.fromJson(m['type']),
    readers: m['readers'] == null ? null : Callers.fromJson(m['readers']),
    meta: (m['meta'] as Map?)?.cast<String, Object?>() ?? const {},
  );

  /// What its payloads must pass.
  final ValueType<Object?> type;

  /// Who may hear it over remote and MCP, as a state's
  /// [StateDescriptor.readers]; null for everyone.
  final Callers? readers;

  @override
  Map<String, Object?> toJson() => {
    'is': 'fact',
    'name': name,
    'type': type.toJson(),
    'readers': ?readers?.toJson(),
    if (meta.isNotEmpty) 'meta': meta,
  };
}

/// Shared representation of the three distinct streaming word descriptors.
sealed class DataStreamDescriptor extends Descriptor {
  /// [params] are inputs, [type] is the type of one element.
  DataStreamDescriptor(
    String name, {
    this.params = const RecordType({}),
    required this.type,
    this.readers,
    Map<String, Object?> meta = const {},
  }) : super(name, meta) {
    readers?.check();
  }

  /// A descriptor received across a connection.
  factory DataStreamDescriptor.fromJson(Map<String, Object?> m) {
    final name = m['name'] as String;
    final params = ValueType.fromJson(m['params']) as RecordType;
    final type = ValueType.fromJson(m['type']);
    final access = m['readers'] ?? m['callers'];
    final readers = access == null ? null : Callers.fromJson(access);
    final meta = (m['meta'] as Map?)?.cast<String, Object?>() ?? const {};
    return switch (m['is']) {
      'clientStream' => ClientStreamDescriptor(
        name,
        params: params,
        input: ValueType.fromJson(m['input']),
        type: type,
        callers: readers,
        meta: meta,
      ),
      'bidiStream' => BidiStreamDescriptor(
        name,
        params: params,
        input: ValueType.fromJson(m['input']),
        type: type,
        callers: readers,
        meta: meta,
      ),
      _ => ServerStreamDescriptor(
        name,
        params: params,
        type: type,
        readers: readers,
        meta: meta,
      ),
    };
  }

  /// Its atomic word kind in catalogs and compatibility schemas.
  String get kind;

  /// Input elements, absent for a server stream.
  ValueType<Object?>? get input => null;

  /// Rebuilds the same kind with resolved access rules.
  DataStreamDescriptor withAccess(Callers access) =>
      DataStreamDescriptor.fromJson({...toJson(), 'readers': access.toJson()});

  /// Parameters fixed for this subscription.
  final RecordType params;

  /// The type of one element.
  final ValueType<Object?> type;

  /// Who may subscribe; null means everyone.
  final Callers? readers;
  @override
  Map<String, Object?> toJson() => {
    'is': kind,
    if (input != null) 'input': input!.toJson(),
    'name': name,
    'params': params.toJson(),
    'type': type.toJson(),
    if (readers != null)
      (input == null ? 'readers' : 'callers'): readers!.toJson(),
    if (meta.isNotEmpty) 'meta': meta,
  };
}

/// A parameterized sequence from the owner to the subscriber.
final class ServerStreamDescriptor extends DataStreamDescriptor {
  /// Creates a server stream word.
  ServerStreamDescriptor(
    super.name, {
    super.params,
    required super.type,
    super.readers,
    super.meta,
  });
  @override
  String get kind => 'serverStream';
}

/// A stream of input with one result.
final class ClientStreamDescriptor extends DataStreamDescriptor {
  /// Creates a distinct client stream word.
  ClientStreamDescriptor(
    super.name, {
    super.params,
    required this.input,
    required super.type,
    Callers? callers,
    super.meta,
  }) : super(readers: callers);
  @override
  final ValueType<Object?> input;
  @override
  String get kind => 'clientStream';
}

/// A bidirectional stream operation.
final class BidiStreamDescriptor extends DataStreamDescriptor {
  /// Creates a distinct bidi stream word.
  BidiStreamDescriptor(
    super.name, {
    super.params,
    required this.input,
    required super.type,
    Callers? callers,
    super.meta,
  }) : super(readers: callers);
  @override
  final ValueType<Object?> input;
  @override
  String get kind => 'bidiStream';
}

/// Binds publication to its exact principal, rejecting foreign addresses.
extension DescriptorAddress on Descriptor {
  /// A runtime descriptor, with an address instead of its portable name.
  Descriptor atTarget(Principal principal) {
    final target = principal.whole;
    if (name.contains('/')) {
      if (WordAddress.parse(name).target != target) {
        throw ArgumentError('$principal cannot provide $name');
      }
      return this;
    }
    return Descriptor.fromJson({
      ...toJson(),
      'name': WordAddress(target, name).toString(),
    });
  }
}
