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

  /// Latest lifecycle observation of a stream or metadata-only operation.
  JournalDiagnostic? diagnostic;

  /// A parent is absent from the loaded recording.
  bool missingParent = false;

  /// Multiple executions share an ID and cannot be attributed uniquely.
  bool ambiguous = false;

  /// Admission and retry decisions belonging to this operation.
  final List<JournalDiagnostic> decisions = [];

  final List<JournalNode> children = [];

  String get id => entry.id;

  /// `call`, `fact` or `write`.
  String get kind => switch (entry) {
    JournalStart() || JournalEnd() => 'call',
    JournalFact() => 'fact',
    JournalWrite() => 'write',
    JournalDiagnostic(:final event) =>
      event.startsWith('stream.') ? 'stream' : 'diagnostic',
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
    if (missingParent) 'missingParent': true,
    if (ambiguous) 'ambiguous': true,
    if (diagnostic != null) ...{
      'event': diagnostic!.event,
      'data': diagnostic!.data,
    },
    if (end case final e?) ...{
      'ended': e.call.finished.toUtc().toIso8601String(),
      'ms': e.call.finished.difference(e.call.started).inMilliseconds,
      'result': e.call.toJson(payloads: payloads && e.payloads)['result'],
      if (e.call.late) 'late': true,
      if (e.call.replyResult != null)
        'replyResult': e.call.replyResult!.toJson(),
      if (e.call.repliedAt != null)
        'repliedAt': e.call.repliedAt!.toUtc().toIso8601String(),
    },
    if (payloads && entry.payloads)
      ...switch (entry) {
        JournalStart(:final call) => {'params': call.params},
        JournalEnd(:final call) => {'params': call.params},
        JournalFact(:final fact) => {'payload': fact.payload},
        JournalDiagnostic() => const <String, Object?>{},
        JournalWrite(:final change) => {
          'key': ?change.key,
          'value': change.value,
          if (change.removed) 'removed': true,
        },
      },
    if (decisions.isNotEmpty)
      'decisions': [for (final d in decisions) d.toJson()],
    'children': [for (final c in children) c.toJson(payloads: payloads)],
  };
}

/// [entries] of one conversation, in order, as trees: the first message
/// is a root, and so is one whose parent is not among them (a day not
/// read, a message the journal does not keep).
List<JournalNode> treeOf(Iterable<JournalEntry> entries) {
  final byId = <(String, String), List<JournalNode>>{};
  final nodes = <JournalNode>[];
  for (final e in entries) {
    final matches = byId.putIfAbsent((e.epoch, e.id), () => []);
    if (e is JournalEnd && matches.isNotEmpty) {
      final calls = matches.where((n) => n.kind == 'call').toList();
      if (calls.isNotEmpty) {
        calls.last._end = e;
        if (calls.length > 1 || e.call.ambiguous) {
          for (final n in calls) {
            n.ambiguous = true;
          }
        }
        continue;
      }
    }
    if (e is JournalDiagnostic &&
        e.event.startsWith('stream.') &&
        matches.isNotEmpty) {
      matches.last.diagnostic = e;
      continue;
    }
    final node = JournalNode._(e, e is JournalEnd ? e : null);
    if (e case JournalStart(:final call) when call.ambiguous) {
      node.ambiguous = true;
    }
    if (e case JournalEnd(:final call) when call.ambiguous) {
      node.ambiguous = true;
    }
    if (e is JournalDiagnostic) node.diagnostic = e;
    if (matches.isNotEmpty) {
      node.ambiguous = true;
      for (final earlier in matches) {
        earlier.ambiguous = true;
      }
    }
    matches.add(node);
    nodes.add(node);
  }
  final roots = <JournalNode>[];
  final parents = <JournalNode, JournalNode>{};
  for (final node in nodes) {
    final parentId = node.entry.cause.parent;
    final candidates = byId[(node.entry.epoch, parentId)] ?? const [];
    JournalNode? parent;
    for (final candidate in candidates) {
      if (!identical(candidate, node) && candidate.entry.n <= node.entry.n) {
        parent = candidate;
      }
    }
    parent ??= candidates.where((c) => !identical(c, node)).firstOrNull;
    if (parent == null || candidates.length > 1 || parent.ambiguous) {
      if (candidates.length > 1 || parent?.ambiguous == true) {
        node.ambiguous = true;
      }
      node.missingParent = parentId != null;
      roots.add(node);
      continue;
    }
    final visited = {node};
    JournalNode? at = parent;
    while (at != null && visited.add(at)) {
      at = parents[at];
    }
    if (at != null) {
      node.ambiguous = true;
      roots.add(node);
      continue;
    }
    parents[node] = parent;
    if (node.entry case JournalDiagnostic(
      :final data,
    ) when data['operation'] == parent.id) {
      parent.decisions.add(node.entry as JournalDiagnostic);
    } else {
      parent.children.add(node);
    }
  }
  return roots;
}
