import 'dart:async';
import 'dart:convert';

import 'package:material_ui/material_ui.dart';

import '../home.dart';
import '../viewer.dart';
import 'client.dart';
import 'live_facts.dart';

typedef JournalHost = ({String device, String prefix, bool supported});

class LiveJournal extends StatefulWidget {
  const LiveJournal({
    super.key,
    required this.active,
    required this.client,
    required this.hosts,
    required this.files,
    this.preferred,
  });
  final bool active;
  final ConsoleClient client;
  final List<JournalHost> hosts;
  final Viewer files;
  final String? preferred;
  @override
  State<LiveJournal> createState() => _LiveJournalState();
}

class _LiveJournalState extends State<LiveJournal> {
  Viewer _viewer = Viewer();
  Timer? _timer;
  String? _device, _prefix, _error;
  int _cursor = 0, _dropped = 0, _generation = 0;
  bool _files = false, _paused = false, _busy = false, _ended = false;
  JournalHost? get host =>
      widget.hosts.where((h) => h.device == _device).firstOrNull;

  @override
  void initState() {
    super.initState();
    _device = widget.preferred;
    _syncHost();
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_poll()),
    );
  }

  @override
  void didUpdateWidget(LiveJournal old) {
    super.didUpdateWidget(old);
    _syncHost();
  }

  void _syncHost() {
    _device ??=
        widget.hosts.where((h) => h.supported).firstOrNull?.device ??
        widget.hosts.firstOrNull?.device;
    final h = host;
    // Keep the last view when the device disappears.
    if (h != null && h.prefix != _prefix) {
      _generation++;
      _prefix = h.prefix;
      _cursor = 0;
      _dropped = 0;
      _error = null;
      _ended = false;
      final previous = _viewer;
      _viewer = Viewer();
      WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
      unawaited(_poll());
    }
  }

  Future<void> _poll() async {
    final h = host;
    if (!mounted ||
        !widget.active ||
        _files ||
        _paused ||
        _busy ||
        _ended ||
        h == null ||
        !h.supported) {
      return;
    }
    final generation = _generation;
    _busy = true;
    try {
      for (var page = 0; page < 8; page++) {
        final response = await widget.client.call('${h.prefix}_journal', {
          'after': _cursor,
        });
        if (!mounted ||
            generation != _generation ||
            _files ||
            _paused ||
            host?.prefix != h.prefix) {
          return;
        }
        final data = jsonDecode(
          ConsoleClient.resultText(response),
        ) as Map<String, dynamic>;
        final lines = (data['lines'] as List<dynamic>).cast<String>();
        final cursor = data['cursor'] as int;
        if (cursor < _cursor || (data['more'] == true && cursor == _cursor)) {
          throw const FormatException('Invalid journal cursor');
        }
        _viewer.appendLive(lines);
        setState(() {
          _cursor = cursor;
          _dropped += data['dropped'] as int;
          _ended = data['ended'] == true && data['more'] != true;
          _error = data['error'] as String?;
        });
        if (data['more'] != true) break;
      }
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(() => _error = e.toString());
      }
    } finally {
      _busy = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _viewer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final choices = {for (final h in widget.hosts) h.device, ?_device};
    final h = host;
    final status = h == null
        ? (_device == null ? 'No connected hosts' : 'Host disconnected')
        : !h.supported
        ? 'Full journal unavailable. This host exposes individual facts.'
        : _error ?? (_ended ? 'Journal stream ended' : null);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Wrap(
            spacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ChoiceChip(
                label: const Text('Live'),
                selected: !_files,
                onSelected: (_) {
                  setState(() => _files = false);
                  unawaited(_poll());
                },
              ),
              ChoiceChip(
                label: const Text('Files'),
                selected: _files,
                onSelected: (_) => setState(() => _files = true),
              ),
              if (!_files && choices.isNotEmpty)
                DropdownButton<String>(
                  value: _device,
                  items: [
                    for (final name in choices)
                      DropdownMenuItem(value: name, child: Text(name)),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      setState(() {
                        _device = v;
                        _paused = false;
                        _syncHost();
                      });
                    }
                  },
                ),
              if (!_files && h?.supported == true)
                IconButton(
                  tooltip: _paused ? 'Resume journal' : 'Pause journal',
                  icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
                  onPressed: () {
                    setState(() => _paused = !_paused);
                    unawaited(_poll());
                  },
                ),
            ],
          ),
        ),
        if (!_files && status != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: SelectableText(status),
          ),
        if (!_files && _dropped > 0)
          Text('$_dropped entries missed before the retained window'),
        Expanded(
          child: _files
              ? Home(key: const ValueKey('files'), viewer: widget.files)
              : (h?.supported == true || _viewer.entries.isNotEmpty)
              ? Home(key: ValueKey(_viewer), viewer: _viewer, live: true)
              : h != null
              ? LiveFacts(
                  key: ValueKey(h.prefix),
                  client: widget.client,
                  prefix: h.prefix,
                  active: widget.active,
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}
