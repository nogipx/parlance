import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:parlance/registry.dart';
import 'package:parlance_journal/journal.dart';

import 'look.dart';
import 'viewer.dart';

/// A row of the waterfall: a message and how deep it is in its tree.
typedef _Line = ({JournalNode node, int depth});

/// The conversation chosen as a tree laid on its time: each message under
/// the one it followed from, a call as a bar from its start to its end
/// (to now while it runs), a fact and a write as a mark.
class Waterfall extends StatelessWidget {
  const Waterfall({super.key, required this.viewer});

  final Viewer viewer;

  static const rowHeight = 26.0;
  static const labelWidth = 360.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final talk = viewer.selected;
    if (talk == null) {
      return Center(
        child: Text('Choose a conversation', style: theme.textTheme.bodySmall),
      );
    }
    final lines = <_Line>[];
    void walk(JournalNode n, int depth) {
      lines.add((node: n, depth: depth));
      for (final c in n.children) {
        walk(c, depth + 1);
      }
    }

    for (final r in viewer.tree) {
      walk(r, 0);
    }
    if (lines.isEmpty) {
      return Center(
        child: Text('Not begun yet', style: theme.textTheme.bodySmall),
      );
    }
    final t0 = talk.started;
    final now = viewer.playhead;
    DateTime endOf(JournalNode n) {
      if (n.end case final e?) return e.call.finished;
      if (n.kind == 'call') return now ?? talk.last;
      return n.entry.at;
    }

    var t1 = t0;
    for (final l in lines) {
      final e = endOf(l.node);
      if (e.isAfter(t1)) t1 = e;
    }
    final span = math.max(1, t1.difference(t0).inMicroseconds);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(talk: talk, span: t1.difference(t0)),
        const Divider(height: 1),
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) {
              final barWidth = math.max(80.0, box.maxWidth - labelWidth - 72);
              return ListView.builder(
                itemCount: lines.length,
                itemExtent: rowHeight,
                itemBuilder: (context, i) {
                  final l = lines[i];
                  final n = l.node;
                  final start = n.end != null && n.kind == 'call'
                      ? n.end!.call.started
                      : n.entry.at;
                  double x(DateTime at) =>
                      at.difference(t0).inMicroseconds / span * barWidth;
                  return _Row(
                    node: n,
                    depth: l.depth,
                    left: x(start),
                    width: n.kind == 'call'
                        ? math.max(2, x(endOf(n)) - x(start))
                        : null,
                    took: n.kind == 'call' ? endOf(n).difference(start) : null,
                    running: n.kind == 'call' && n.end == null,
                    chosen: viewer.node?.id == n.id,
                    onTap: () => viewer.choose(n),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.talk, required this.span});

  final JournalConversation talk;
  final Duration span;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dim = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${talk.origin.word} by ${talk.origin.by}',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                SelectableText(
                  '${dayClockOf(talk.started)}   conversation ${talk.id}',
                  style: dim,
                ),
              ],
            ),
          ),
          Text(spanOf(span), style: dim),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.node,
    required this.depth,
    required this.left,
    required this.width,
    required this.took,
    required this.running,
    required this.chosen,
    required this.onTap,
  });

  final JournalNode node;
  final int depth;
  final double left;

  /// A call's bar; null for a mark.
  final double? width;
  final Duration? took;
  final bool running;
  final bool chosen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = Look.of(node);
    final dim = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final key = switch (node.entry) {
      JournalWrite(:final change) when change.key != null => '[${change.key}]',
      _ => '',
    };
    return Material(
      color: chosen
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            SizedBox(
              width: Waterfall.labelWidth,
              child: Padding(
                padding: EdgeInsets.only(left: 12 + depth * 14.0, right: 8),
                child: Row(
                  children: [
                    Icon(Look.iconOf(node), size: 14, color: color),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '${node.word}$key',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '${node.by}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: dim,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: left,
                    top: width == null ? 8 : 7,
                    child: width == null
                        ? Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                            ),
                          )
                        : Container(
                            width: width,
                            height: 12,
                            decoration: BoxDecoration(
                              color: color.withValues(
                                alpha: running ? 0.55 : 0.9,
                              ),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                  ),
                  if (took case final t?)
                    Positioned(
                      left: left + (width ?? 0) + 6,
                      top: 5,
                      child: Text(
                        running ? '${spanOf(t)}…' : spanOf(t),
                        style: dim,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
