import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'look.dart';
import 'viewer.dart';

/// Plays the journal back as it happened: a playhead over all that was
/// loaded, which the conversations and the tree show only up to; faster
/// than it happened, and over quiet stretches at once.
class PlaybackBar extends StatefulWidget {
  const PlaybackBar({super.key, required this.viewer});

  final Viewer viewer;

  @override
  State<PlaybackBar> createState() => _PlaybackBarState();
}

class _PlaybackBarState extends State<PlaybackBar>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  Duration _lastTick = Duration.zero;

  static const speeds = [1.0, 10.0, 60.0, 600.0];

  Viewer get v => widget.viewer;

  @override
  void initState() {
    super.initState();
    v.addListener(_follow);
  }

  @override
  void dispose() {
    v.removeListener(_follow);
    _ticker.dispose();
    super.dispose();
  }

  void _follow() {
    if (v.playing && !_ticker.isActive) {
      _lastTick = Duration.zero;
      _ticker.start();
    } else if (!v.playing && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _tick(Duration elapsed) {
    final wall = elapsed - _lastTick;
    _lastTick = elapsed;
    v.advance(wall);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final first = v.first, last = v.last;
    if (first == null || last == null) return const SizedBox.shrink();
    final total = math.max(1, last.difference(first).inMilliseconds);
    final at = v.playhead;
    final dim = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            tooltip: v.playing ? 'Pause' : 'Play back',
            icon: Icon(v.playing ? Icons.pause : Icons.play_arrow),
            onPressed: v.playing ? v.pause : v.play,
          ),
          IconButton(
            tooltip: 'Show everything',
            icon: const Icon(Icons.stop),
            onPressed: at == null ? null : v.stop,
          ),
          SizedBox(
            width: 170,
            child: Text(
              at == null ? 'everything' : dayClockOf(at),
              style: Look.mono,
            ),
          ),
          Expanded(
            child: Slider(
              value: at == null
                  ? total.toDouble()
                  : at.difference(first).inMilliseconds.clamp(0, total) / 1.0,
              max: total.toDouble(),
              onChanged: (x) =>
                  v.seek(first.add(Duration(milliseconds: x.round()))),
            ),
          ),
          for (final s in speeds)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: ChoiceChip(
                label: Text('${s.toInt()}×'),
                selected: v.speed == s,
                onSelected: (_) => v.speed = s,
              ),
            ),
          const SizedBox(width: 8),
          Tooltip(
            message: 'Jump over stretches where nothing happens',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Checkbox(
                  value: v.skipQuiet,
                  onChanged: (x) => v.skipQuiet = x ?? true,
                ),
                Text('skip quiet', style: dim),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
