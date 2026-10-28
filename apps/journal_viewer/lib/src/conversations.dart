import 'package:flutter/material.dart';
import 'package:parlance_journal/journal.dart';

import 'look.dart';
import 'viewer.dart';

/// The conversations loaded, as filtered: when each started, what with
/// and by whom, how long it went on and how its calls ended.
class ConversationList extends StatelessWidget {
  const ConversationList({super.key, required this.viewer});

  final Viewer viewer;

  @override
  Widget build(BuildContext context) {
    final talks = viewer.conversations;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: TextField(
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search, size: 18),
              hintText: 'Word, who or id',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => viewer.query = v,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Flexible(
                child: Tooltip(
                  message:
                      'Only those with a call refused, failed or timed out',
                  child: FilterChip(
                    label: const Text('Problems'),
                    selected: viewer.problemsOnly,
                    onSelected: (v) => viewer.problemsOnly = v,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '${talks.length} of ${viewer.all.length}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        const Divider(height: 1),
        Expanded(
          child: talks.isEmpty
              ? Center(
                  child: Text(
                    'No conversation',
                    style: theme.textTheme.bodySmall,
                  ),
                )
              : ListView.builder(
                  itemCount: talks.length,
                  itemExtent: 58,
                  itemBuilder: (context, i) => _Row(
                    talk: talks[i],
                    selected:
                        identical(talks[i], viewer.selected) ||
                        (viewer.selected?.id == talks[i].id &&
                            viewer.selected?.epoch == talks[i].epoch),
                    onTap: () => viewer.select(talks[i]),
                  ),
                ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.talk, required this.selected, required this.onTap});

  final JournalConversation talk;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dim = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Material(
      color: selected
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      talk.origin.word,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${clockOf(talk.started)}  ${talk.origin.by}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: dim,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(spanOf(talk.duration), style: dim),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _Count(talk.entries, null, Icons.notes),
                      if (talk.refused > 0)
                        _Count(talk.refused, Look.refused, Icons.block),
                      if (talk.failed > 0)
                        _Count(talk.failed, Look.failed, Icons.error_outline),
                      if (talk.timedOut > 0)
                        _Count(talk.timedOut, Look.slow, Icons.timer_outlined),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count(this.n, this.color, this.icon);

  final int n;
  final Color? color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: c),
          const SizedBox(width: 2),
          Text('$n', style: TextStyle(fontSize: 12, color: c)),
        ],
      ),
    );
  }
}
