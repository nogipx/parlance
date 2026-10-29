import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:parlance/registry.dart';

import 'look.dart';
import 'viewer.dart';

/// The message chosen: what it was, on whose behalf, following what, how
/// a call ended, its values, and how it came about.
class Details extends StatelessWidget {
  const Details({super.key, required this.viewer});

  final Viewer viewer;

  static const _json = JsonEncoder.withIndent('  ');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final n = viewer.node;
    if (n == null) {
      return Center(
        child: Text('Choose a message', style: theme.textTheme.bodySmall),
      );
    }
    final e = n.entry;
    final cause = e.cause;
    final values = switch (e) {
      JournalStart(:final call) => {'params': call.params},
      JournalEnd(:final call) => {'params': call.params},
      JournalFact(:final fact) => {'payload': fact.payload},
      JournalWrite(:final change) => {
        'key': ?change.key,
        'value': change.value,
        'previous': change.previous,
        if (change.removed) 'removed': true,
      },
    };
    final end = n.end?.call;
    final path = viewer.pathToNode;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(
          children: [
            Icon(Look.iconOf(n), size: 16, color: Look.of(n)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '${n.kind} ${n.word}',
                style: theme.textTheme.titleSmall,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _Field('by', '${cause.by}'),
        _Field('at', dayClockOf(e.at) + clockOf(e.at).substring(8)),
        _Field('id', e.id),
        if (cause.parent case final p?) _Field('follows', p),
        _Field('conversation', e.conversation),
        _Field('started with', '${e.origin}'),
        if (e.trace case final t?) _Field('trace', t),
        _Field('journal', '${e.epoch} #${e.n}'),
        if (end != null) ...[
          const SizedBox(height: 10),
          _Field('ended', outcomeOf(n) ?? ''),
          _Field('took', spanOf(end.finished.difference(end.started))),
          if (end.result case CallRefused(:final reason, :final guard)) ...[
            _Field('why', reason),
            if (guard != null) _Field('guard', guard),
          ],
          if (end.result case CallFailed(:final error))
            _Field('error', '$error'),
          if (end.result case CallDone(:final value) when value != null)
            _Block('answer', _json.convert(value)),
        ],
        const SizedBox(height: 10),
        _Block('values', _json.convert(values)),
        if (path.length > 1) ...[
          const SizedBox(height: 10),
          Text('How it came about', style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          for (final (i, p) in path.indexed)
            Padding(
              padding: EdgeInsets.only(left: i * 10.0, top: 2),
              child: Text(
                '${p.kind} ${p.word}  ${p.cause.by}',
                style: Look.mono,
              ),
            ),
        ],
        const SizedBox(height: 10),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text('As written', style: theme.textTheme.labelLarge),
          children: [
            SelectableText(_json.convert(e.toJson()), style: Look.mono),
            if (n.end case final x? when !identical(x, e)) ...[
              const SizedBox(height: 8),
              SelectableText(_json.convert(x.toJson()), style: Look.mono),
            ],
          ],
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field(this.name, this.value);

  final String name;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              name,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: SelectableText(value, style: Look.mono)),
        ],
      ),
    );
  }
}

class _Block extends StatelessWidget {
  const _Block(this.name, this.text);

  final String name;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(name, style: theme.textTheme.labelLarge),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(6),
          ),
          child: SelectableText(text, style: Look.mono),
        ),
      ],
    );
  }
}
