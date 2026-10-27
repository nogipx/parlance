/// Who acts: a kind the host declared and an id within it (SPEC §4).
final class Principal {
  const Principal(this.kind, [this.id = '']);

  factory Principal.fromJson(Object? json) {
    final m = json as Map;
    return Principal(m['kind'] as String, m['id'] as String? ?? '');
  }

  /// The registry itself: layer dispatches, expiry.
  static const system = Principal('system');

  final String kind;
  final String id;

  /// `kind:id`, or just the kind when there is no id.
  String get selector => id.isEmpty ? kind : '$kind:$id';

  static final RegExp _part = RegExp(r'^[a-z0-9][a-z0-9_-]*$');

  /// A part of this one, named [name] (SPEC §4): `studio` → `studio:sound`,
  /// `module:orders` → `module:orders/sync`. What names this one names its
  /// parts too, unless something names the part.
  Principal child(String name) {
    if (!_part.hasMatch(name)) {
      throw ArgumentError.value(name, 'name', 'lower-case words, - and _');
    }
    return Principal(kind, id.isEmpty ? name : '$id/$name');
  }

  /// Whether this is [other] or a part of it, at any depth.
  bool isWithin(Principal other) =>
      kind == other.kind &&
      (other.id.isEmpty || id == other.id || id.startsWith('${other.id}/'));

  /// The one this is a part of; null for a whole.
  Principal? get parent {
    if (id.isEmpty) return null;
    final i = id.lastIndexOf('/');
    return i < 0 ? Principal(kind) : Principal(kind, id.substring(0, i));
  }

  Map<String, Object?> toJson() => {'kind': kind, if (id.isNotEmpty) 'id': id};

  @override
  bool operator ==(Object other) =>
      other is Principal && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);

  @override
  String toString() => selector;
}

/// Why something happens (SPEC §4).
final class Cause {
  const Cause(this.by, {this.parent, this.chain = const [], this.test = false});

  factory Cause.fromJson(Object? json) {
    final m = json as Map;
    return Cause(
      Principal.fromJson(m['by']),
      parent: m['parent'] as String?,
      chain: [for (final c in m['chain'] as List? ?? const []) c as String],
      test: m['test'] == true,
    );
  }

  /// On whose behalf.
  final Principal by;

  /// The message this one follows from: the call whose handler wrote it.
  final String? parent;

  /// The links and hooks this came through, oldest first; how loops are
  /// found.
  final List<String> chain;

  /// Everything a trial run caused.
  final bool test;

  /// The cause of what a message caused: [parent] is that message, the
  /// chain and the test mark carry over, [by] and [through] may change.
  Cause child(String parentId, {Principal? by, String? through}) => Cause(
    by ?? this.by,
    parent: parentId,
    chain: through == null ? chain : [...chain, through],
    test: test,
  );

  bool came(String through) => chain.contains(through);

  /// The same cause, on behalf of [by].
  Cause withBy(Principal by) =>
      Cause(by, parent: parent, chain: chain, test: test);

  Map<String, Object?> toJson() => {
    'by': by.toJson(),
    'parent': ?parent,
    if (chain.isNotEmpty) 'chain': chain,
    if (test) 'test': true,
  };

  @override
  String toString() =>
      'Cause($by${parent == null ? '' : ' <- $parent'}'
      '${chain.isEmpty ? '' : ' via ${chain.join('>')}'}${test ? ' test' : ''})';
}
