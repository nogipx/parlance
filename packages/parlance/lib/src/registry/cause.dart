import 'dart:convert';

/// Who acts: a kind the host declared, an id within it, and the owner of
/// it that acts, if one does (SPEC §4).
final class Principal {
  const Principal(this.kind, [this.id = '', this.owner = '']);

  factory Principal.fromJson(Object? json) {
    final m = json as Map;
    return Principal(
      m['kind'] as String,
      m['id'] as String? ?? '',
      m['owner'] as String? ?? '',
    )..check();
  }

  /// The registry itself: the values of a word that went, removed with it.
  static const system = Principal('system');

  final String kind;

  /// One level, maybe from outside; empty for a kind of one (`studio`).
  final String id;

  /// The owner of it that acts ([child]); empty for the whole.
  final String owner;

  /// Its selector (SPEC §4): `kind[/id][@owner]` (`user/local`,
  /// `studio@screen`, `plugin/hydra@ui`, `member/forum.123`).
  String get selector =>
      '$kind${id.isEmpty ? '' : '/$id'}${owner.isEmpty ? '' : '@$owner'}';

  /// Its parts (SPEC §4). A kind and an owner's name are ours, as a word's
  /// name is: lower-case letters and digits joined by `_` or `-`. An id may
  /// come from outside: letters, digits, `.`, `-` and `_`, its case kept
  /// (`levelOf` makes one of any text). So `/` and `@` are only ever
  /// separators, and every other sign is reserved.
  static final RegExp _kind = RegExp(r'^[a-z][a-z0-9_-]*$');
  static final RegExp _owner = RegExp(r'^[a-z0-9][a-z0-9_-]*$');
  static final RegExp _level = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$');
  static final RegExp _outside = RegExp(r'[^A-Za-z0-9._-]+');

  /// An id made of [text] from outside (a member's id, a device's name),
  /// by the rule Kubernetes and Helm name things by: a text that is one
  /// already stays as it is; else every run of other signs becomes `_` and
  /// a hash of the whole text is added after a `.` (`ann@mail.com` →
  /// `ann_mail.com.<hash>`), so two texts never become one id.
  static String levelOf(String text) {
    if (_level.hasMatch(text)) return text;
    var slug = text.replaceAll(_outside, '_');
    if (slug.isEmpty || !RegExp('^[A-Za-z0-9]').hasMatch(slug)) {
      slug = 'x$slug';
    }
    if (slug.length > 64) slug = slug.substring(0, 64);
    return '$slug.${_fnv1a(text)}';
  }

  /// FNV-1a, 32 bits, of [text]'s UTF-8, as 8 hex digits.
  static String _fnv1a(String text) {
    var h = 0x811c9dc5;
    for (final b in utf8.encode(text)) {
      h ^= b;
      // h * 0x01000193 by shifts and adds: exact in JavaScript too, where
      // a product past 2^53 would not be.
      h =
          (h + (h << 1) + (h << 4) + (h << 7) + (h << 8) + (h << 24)) &
          0xffffffff;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }

  /// The principal [selector] names: `kind[/id][@owner]`.
  factory Principal.parse(String selector) {
    var rest = selector;
    var owner = '';
    final at = rest.indexOf('@');
    if (at >= 0) {
      owner = rest.substring(at + 1);
      rest = rest.substring(0, at);
      if (owner.isEmpty) throw ArgumentError.value(selector, 'owner', 'empty');
    }
    final i = rest.indexOf('/');
    final p = i < 0
        ? Principal(rest, '', owner)
        : Principal(rest.substring(0, i), rest.substring(i + 1), owner);
    if (i >= 0 && p.id.isEmpty) {
      throw ArgumentError.value(selector, 'id', 'empty');
    }
    p.check();
    return p;
  }

  /// Throws when its kind, id or owner is not one (SPEC §4): so a
  /// principal from outside is the parts it says.
  void check() {
    if (!_kind.hasMatch(kind)) {
      throw ArgumentError.value(
        kind,
        'kind',
        'lower-case letters and digits joined by _ or -, from a letter',
      );
    }
    if (id.isNotEmpty && !_level.hasMatch(id)) {
      throw ArgumentError.value(
        id,
        'id',
        'letters, digits, ., - and _, from a letter or digit '
            '(Principal.levelOf makes one of any text)',
      );
    }
    if (owner.isNotEmpty && !_owner.hasMatch(owner)) {
      throw ArgumentError.value(
        owner,
        'owner',
        'lower-case letters and digits joined by _ or -',
      );
    }
  }

  /// Its owner named [name] (SPEC §4): `studio` → `studio@screen`,
  /// `plugin/hydra` → `plugin/hydra@ui`. What names the whole names its
  /// owners too, unless something names the owner. An owner has none.
  Principal child(String name) {
    if (owner.isNotEmpty) {
      throw StateError('$selector is an owner: it has no parts');
    }
    if (!_owner.hasMatch(name)) {
      throw ArgumentError.value(
        name,
        'name',
        'lower-case letters and digits joined by _ or -',
      );
    }
    return Principal(kind, id, name);
  }

  /// Whether a selector of [other] names this one: [other] itself, its
  /// owners, and for a bare kind every principal of it.
  bool isWithin(Principal other) {
    if (kind != other.kind) return false;
    if (other.owner.isNotEmpty) return this == other;
    return other.id.isEmpty || id == other.id;
  }

  /// The one this is a part of: the whole of an owner, the kind of an id;
  /// null for a bare kind.
  Principal? get parent {
    if (owner.isNotEmpty) return Principal(kind, id);
    if (id.isNotEmpty) return Principal(kind);
    return null;
  }

  Map<String, Object?> toJson() => {
    'kind': kind,
    if (id.isNotEmpty) 'id': id,
    if (owner.isNotEmpty) 'owner': owner,
  };

  @override
  bool operator ==(Object other) =>
      other is Principal &&
      other.kind == kind &&
      other.id == id &&
      other.owner == owner;

  @override
  int get hashCode => Object.hash(kind, id, owner);

  @override
  String toString() => selector;
}

/// Why something happens (SPEC §4).
final class Cause {
  const Cause(this.by, {this.parent, this.correlation});

  factory Cause.fromJson(Object? json) {
    final m = json as Map;
    return Cause(
      Principal.fromJson(m['by']),
      parent: m['parent'] as String?,
      correlation: m['correlation'] as String?,
    );
  }

  /// On whose behalf.
  final Principal by;

  /// The message this one follows from: the call whose handler wrote it.
  final String? parent;

  /// The conversation this one is part of: the id of the message that set
  /// it all going, the same for everything that followed from it, however
  /// far (a message come in, the call it led to, the timer that call set). Null
  /// for a message that starts one: its conversation is its own id
  /// ([conversationOf]).
  final String? correlation;

  /// The conversation of the message of [id] this cause is of.
  String conversationOf(String id) => correlation ?? id;

  /// The cause of what a message caused: [parent] is that message, [by]
  /// may change; it stays in the message's conversation.
  Cause child(String parentId, {Principal? by}) => Cause(
    by ?? this.by,
    parent: parentId,
    correlation: correlation ?? parentId,
  );

  /// The same cause, on behalf of [by].
  Cause withBy(Principal by) =>
      Cause(by, parent: parent, correlation: correlation);

  Map<String, Object?> toJson() => {
    'by': by.toJson(),
    'parent': ?parent,
    'correlation': ?correlation,
  };

  @override
  String toString() =>
      'Cause($by${parent == null ? '' : ' <- $parent'}'
      '${correlation == null ? '' : ' in $correlation'})';
}
