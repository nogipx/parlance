import 'dart:convert';

import 'package:crypto/crypto.dart' show sha256;

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

  /// Which one of its kind, maybe from outside; empty for a kind of one
  /// (`house`).
  final String id;

  /// The owner of it that acts ([child]); empty for the whole.
  final String owner;

  /// Its selector (SPEC §4): `kind[/id][@owner]` (`user/local`,
  /// `home@house`, `module/visit@visit`, `member/forum.123`).
  String get selector =>
      '$kind${id.isEmpty ? '' : '/$id'}${owner.isEmpty ? '' : '@$owner'}';

  /// Its parts (SPEC §4). A kind and an owner's name are ours, as a word's
  /// name is: lower-case letters and digits joined by `_` or `-`. An id may
  /// come from outside: letters, digits, `.`, `-` and `_`, its case kept
  /// (`idOf` makes one of any text). So `/` and `@` are only ever
  /// separators, and every other sign is reserved.
  static final RegExp _kind = RegExp(r'^[a-z][a-z0-9_-]*$');
  static final RegExp _owner = RegExp(r'^[a-z0-9][a-z0-9_-]*$');
  static final RegExp _id = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$');
  static final RegExp _outside = RegExp(r'[^A-Za-z0-9._-]+');

  /// An id made of [text] from outside (a member's id, a device's name),
  /// by the rule Kubernetes and Helm name things by: a text that is one
  /// already stays as it is; else every run of other signs becomes `_` and
  /// a hash of the whole text is added after a `.` (`ann@mail.com` →
  /// `ann_mail.com.<hash>`), so two texts never become one id. The hash is
  /// 64 bits of SHA-256, so no one finds a text that makes another's id;
  /// and a text that ends as one made so (`.` and 16 hex digits) is made
  /// one too, so no one is given another's id by taking it as a name.
  static String idOf(String text) {
    if (_id.hasMatch(text) && !_made.hasMatch(text)) return text;
    var slug = text.replaceAll(_outside, '_');
    if (slug.isEmpty || !RegExp('^[A-Za-z0-9]').hasMatch(slug)) {
      slug = 'x$slug';
    }
    if (slug.length > 64) slug = slug.substring(0, 64);
    final hash = sha256.convert(utf8.encode(text)).toString();
    return '$slug.${hash.substring(0, 16)}';
  }

  /// How an id [idOf] made ends.
  static final RegExp _made = RegExp(r'\.[0-9a-f]{16}$');

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
    if (id.isNotEmpty && !_id.hasMatch(id)) {
      throw ArgumentError.value(
        id,
        'id',
        'letters, digits, ., - and _, from a letter or digit '
            '(Principal.idOf makes one of any text)',
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

  /// Its owner named [name], its vocabulary's (SPEC §4): `home` →
  /// `home@house`, `module/visit` → `module/visit@visit`. What names the whole names its
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

/// What a conversation started with (SPEC §4): the word of its first
/// message (a command's or a fact's name) and on whose behalf it was. Which
/// conversation it is, the cause's `conversation` (its id) says.
final class Origin {
  const Origin(this.word, this.by);

  factory Origin.fromJson(Object? json) {
    final m = json as Map;
    return Origin(m['word'] as String, Principal.fromJson(m['by']));
  }

  final String word;
  final Principal by;

  Map<String, Object?> toJson() => {'word': word, 'by': by.toJson()};

  @override
  bool operator ==(Object other) =>
      other is Origin && other.word == word && other.by == by;

  @override
  int get hashCode => Object.hash(word, by);

  @override
  String toString() => '$word by $by';
}

/// Why something happens (SPEC §4).
final class Cause {
  const Cause(this.by, {this.parent, this.conversation, this.origin});

  factory Cause.fromJson(Object? json) {
    final m = json as Map;
    return Cause(
      Principal.fromJson(m['by']),
      parent: m['parent'] as String?,
      conversation: m['conversation'] as String?,
      origin: m['origin'] == null ? null : Origin.fromJson(m['origin']),
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
  final String? conversation;

  /// What the conversation started with: the word of its first message
  /// and on whose behalf it was, the same for everything that followed
  /// from it, whoever acts on the way. Null for a message that starts one:
  /// it is its own ([originOf]). The registry gives it
  /// from the message a cause follows from, never takes it from the one
  /// that acts.
  final Origin? origin;

  /// The conversation of the message of [id] this cause is of.
  String conversationOf(String id) => conversation ?? id;

  /// What the conversation of a message of [word] with this cause started
  /// with: [origin], or that message itself.
  Origin originOf(String word) => origin ?? Origin(word, by);

  /// The cause of what a message caused: [parent] is that message (of
  /// [word], when the caller knows it), [by] may change; it stays in the
  /// message's conversation, and keeps its origin.
  Cause child(String parentId, {Principal? by, String? word}) => Cause(
    by ?? this.by,
    parent: parentId,
    conversation: conversation ?? parentId,
    origin: origin ?? (word == null ? null : Origin(word, this.by)),
  );

  /// The same cause, on behalf of [by].
  Cause withBy(Principal by) =>
      Cause(by, parent: parent, conversation: conversation, origin: origin);

  Map<String, Object?> toJson() => {
    'by': by.toJson(),
    'parent': ?parent,
    'conversation': ?conversation,
    'origin': ?origin?.toJson(),
  };

  @override
  String toString() =>
      'Cause($by${parent == null ? '' : ' <- $parent'}'
      '${conversation == null ? '' : ' in $conversation'}'
      '${origin == null ? '' : ' from $origin'})';
}
