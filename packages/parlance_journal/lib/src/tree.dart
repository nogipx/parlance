import 'package:parlance/tools.dart';

/// One message of a conversation in its tree: what it led to are its
/// [children], each one whose cause's parent it is, in the order they
/// happened.
final class JournalNode {
  JournalNode._(this.entry, this._end);

  /// The message: a call as it began (as it ended, when it was refused and
  /// never began), a fact, a write.
  final JournalEntry entry;

  /// How a call ended, when it has: its last end, the late one after a
  /// timeout. Null for a fact, a write, and a call still running.
  JournalEnd? get end => _end;
  JournalEnd? _end;

  final List<JournalNode> children = [];

  String get id => entry.id;

  /// `call`, `fact` or `write`.
  String get kind => switch (entry) {
    JournalStart() || JournalEnd() => 'call',
    JournalFact() => 'fact',
    JournalWrite() => 'write',
  };

  /// The command called, the fact said, the state written.
  String get word => entry.word;

  Principal get by => entry.cause.by;

  /// What a view of the tree draws: who did what when, how a call ended
  /// and how long it took, and what it led to. Values only with
  /// [payloads].
  Map<String, Object?> toJson({bool payloads = false}) => {
    'id': id,
    'kind': kind,
    'word': word,
    'by': by.selector,
    'at': entry.at.toUtc().toIso8601String(),
    if (end case final e?) ...{
      'ended': e.call.finished.toUtc().toIso8601String(),
      'ms': e.call.finished.difference(e.call.started).inMilliseconds,
      'result': {
        for (final r in e.call.result.toJson().entries)
          if (payloads || r.key != 'value') r.key: r.value,
      },
      if (e.call.late) 'late': true,
    },
    if (payloads)
      ...switch (entry) {
        JournalStart(:final call) => {'params': call.params},
        JournalEnd(:final call) => {'params': call.params},
        JournalFact(:final fact) => {'payload': fact.payload},
        JournalWrite(:final change) => {
          'key': ?change.key,
          'value': change.value,
          if (change.removed) 'removed': true,
        },
      },
    'children': [for (final c in children) c.toJson(payloads: payloads)],
  };
}

/// [entries] of one conversation, in order, as trees: the first message
/// is a root, and so is one whose parent is not among them (a day not
/// read, a message the journal does not keep).
List<JournalNode> treeOf(Iterable<JournalEntry> entries) {
  final nodes = <String, JournalNode>{};
  final roots = <JournalNode>[];
  for (final e in entries) {
    if (e is JournalEnd) {
      if (nodes[e.id] case final began?) {
        began._end = e;
        continue;
      }
    }
    final node = nodes[e.id] = JournalNode._(e, e is JournalEnd ? e : null);
    switch (nodes[e.cause.parent]) {
      case final parent?:
        parent.children.add(node);
      case null:
        roots.add(node);
    }
  }
  return roots;
}
