import 'dart:async';
import 'dart:convert';

import 'package:material_ui/material_ui.dart';

import 'client.dart';
import 'inspector.dart';
import 'wifi.dart';
import '../look.dart';
import 'live_journal.dart';
import '../viewer.dart';

typedef Device = ({String app, String name, String? prefix});

class LiveConsole extends StatefulWidget {
  const LiveConsole({super.key, required this.client, required this.viewer});
  final ConsoleClient client;
  final Viewer viewer;
  @override
  State<LiveConsole> createState() => _LiveConsoleState();
}

class _LiveConsoleState extends State<LiveConsole> {
  Timer? _timer;
  var _busy = false, _initialized = false, _paused = false;
  var _tab = 0, _filterRevision = 0;
  int? _cursor;
  String? _device, _error;
  var _level = 'all';
  final _trace = TextEditingController();
  final _deviceColors = <String, Color>{};
  var _devices = <Device>[];
  var _journalHosts = <JournalHost>[];
  bool _openedJournal = false;
  String _logs = '';
  Device? get _selected => _devices.where((d) => d.name == _device).firstOrNull;

  Color _deviceColor(String name) => _deviceColors.putIfAbsent(name, () {
    // Step around the colour wheel by the golden angle to separate neighbours.
    final hue = (212 + 137.508 * _deviceColors.length) % 360;
    return HSLColor.fromAHSL(1, hue, 0.65, 0.68).toColor();
  });

  @override
  void initState() {
    super.initState();
    unawaited(_poll());
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_poll()),
    );
  }

  Future<void> _poll() async {
    if (_busy || !mounted) return;
    _busy = true;
    try {
      final c = widget.client;
      if (!_initialized) {
        await c.initialize();
        _initialized = true;
      }
      final results = await Future.wait([
        c.call('hosts'),
        c.call('rpc_log_sources'),
      ]);
      final catalog =
          jsonDecode(ConsoleClient.resultText(results.first)) as List<dynamic>;
      final sources = results.last;
      final meta = sources['structuredContent'] as Map<String, dynamic>?;
      final devices = <String, Device>{};
      void add(String name, String app, String? prefix) {
        devices[name] = (name: name, app: app, prefix: prefix);
      }

      if (meta != null) {
        for (final source
            in (meta['devices'] as List<dynamic>)
                .cast<Map<String, dynamic>>()) {
          add(source['device'] as String, source['app'] as String, null);
        }
      } else {
        // The released 0.4.0 collector lists log-only devices as text.
        for (final m in RegExp(
          r'^  (.+) \[(.+)\] since \d\d:',
          multiLine: true,
        ).allMatches(ConsoleClient.resultText(sources))) {
          add(m[1]!, m[2]!, null);
        }
      }
      for (final h in catalog.cast<Map<String, dynamic>>()) {
        add(h['device'] as String, h['app'] as String, h['prefix'] as String);
      }
      if (!mounted) return;
      final revision = _filterRevision;
      final cursor = meta?['cursor'] as int?;
      String? latest;
      if (_tab == 0 && !_paused && (cursor == null || cursor != _cursor)) {
        final result = await c.call('rpc_log_get_logs', {
          'count': 200,
          'device': ?_device,
          if (_level != 'all') 'level': _level,
          if (_trace.text.trim().isNotEmpty) 'traceId': _trace.text.trim(),
        });
        latest = ConsoleClient.resultText(result);
      }
      if (!mounted) return;
      setState(() {
        _devices = devices.values.toList()
          ..sort((a, b) => a.name.compareTo(b.name));
        _journalHosts = [
          for (final h in catalog.cast<Map<String, dynamic>>())
            (
              device: h['device'] as String,
              prefix: h['prefix'] as String,
              supported: h['journal'] == true,
            ),
        ];
        _error = null;
        if (!_paused && latest != null && revision == _filterRevision) {
          _logs = latest;
          _cursor = cursor;
        }
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
      if (widget.client.closed) _timer?.cancel();
    } finally {
      _busy = false;
    }
  }

  void _filter(void Function() edit) {
    setState(() {
      edit();
      _filterRevision++;
      _cursor = null;
      _logs = '';
      _paused = false;
    });
    unawaited(_poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.client.close();
    _trace.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Parlance Console'),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.wifi),
            label: const Text('Wi-Fi'),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => WifiDialog(client: widget.client),
            ),
          ),
          for (final entry in ['Logs', 'Inspector', 'Journal'].indexed)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(entry.$2),
                selected: _tab == entry.$1,
                onSelected: (_) => setState(() {
                  _tab = entry.$1;
                  if (_tab == 2) _openedJournal = true;
                }),
              ),
            ),
        ],
      ),
      body: IndexedStack(
        index: _tab == 2 ? 1 : 0,
        children: [
          Column(
            children: [
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: SelectableText(_error!),
                ),
              Expanded(
                child: Row(
                  children: [
                    SizedBox(
                      width: 220,
                      child: ListView(
                        children: [
                          ListTile(
                            title: const Text('All devices'),
                            selected: _device == null,
                            onTap: () => _filter(() => _device = null),
                          ),
                          for (final d in _devices)
                            ListTile(
                              title: Text(d.name),
                              trailing: Icon(
                                Icons.circle,
                                size: 10,
                                color: _deviceColor(d.name),
                              ),
                              subtitle: Text(d.app),
                              selected: _device == d.name,
                              onTap: () => _filter(() => _device = d.name),
                            ),
                          if (_device != null && selected == null)
                            ListTile(
                              title: Text(_device!),
                              trailing: Icon(
                                Icons.circle,
                                size: 10,
                                color: _deviceColor(_device!),
                              ),
                              subtitle: const Text('Disconnected'),
                              selected: true,
                            ),
                        ],
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: _tab != 1
                          ? _logPanel()
                          : selected?.prefix == null
                          ? const Center(
                              child: Text('Select a connected Parlance host'),
                            )
                          : Inspector(
                              key: ValueKey((
                                selected!.prefix,
                                widget.client.catalogRevision,
                              )),
                              client: widget.client,
                              prefix: selected.prefix!,
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_openedJournal)
            LiveJournal(
              active: _tab == 2,
              client: widget.client,
              hosts: _journalHosts,
              preferred: _device,
              files: widget.viewer,
            ),
        ],
      ),
    );
  }

  Widget _logPanel() {
    final lines = _logs.split('\n');
    final rows = lines.skip(1).toList().reversed.toList();
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              DropdownButton<String>(
                value: _level,
                items: [
                  for (final v in [
                    'all',
                    'debug',
                    'info',
                    'warning',
                    'error',
                    'fatal',
                  ])
                    DropdownMenuItem(
                      value: v,
                      child: Text(v == 'all' ? 'All levels' : v),
                    ),
                ],
                onChanged: (v) {
                  if (v != null) _filter(() => _level = v);
                },
              ),
              SizedBox(
                width: 200,
                child: TextField(
                  controller: _trace,
                  decoration: const InputDecoration(labelText: 'Trace ID'),
                  onChanged: (_) => _filter(() {}),
                ),
              ),
              IconButton(
                tooltip: _paused ? 'Resume' : 'Pause',
                icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
                onPressed: () => setState(() => _paused = !_paused),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_logs.isNotEmpty)
            Text(lines.first, style: Theme.of(context).textTheme.labelMedium),
          const Divider(),
          Expanded(
            child: rows.isEmpty
                ? Center(
                    child: Text(
                      _logs.isEmpty
                          ? 'Waiting for logs…'
                          : 'No matching records',
                    ),
                  )
                : ListView.builder(
                    itemCount: rows.length,
                    itemBuilder: (context, i) {
                      final line = rows[i];
                      final entry = Look.logLine(line);
                      final trace = RegExp(r'\btrace=([\da-fA-F]+)')
                          .firstMatch(line)
                          ?.group(1);
                      return ColoredBox(
                        color: switch (entry.device) {
                          final device? => _deviceColor(
                            device,
                          ).withValues(alpha: 0.14),
                          null => Colors.transparent,
                        },
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: SelectableText.rich(
                                  entry.text,
                                  style: Look.mono,
                                ),
                              ),
                            ),
                            if (trace != null)
                              IconButton(
                                tooltip: 'Filter by this trace',
                                icon: const Icon(
                                  Icons.filter_alt_outlined,
                                  size: 16,
                                ),
                                onPressed: () =>
                                    _filter(() => _trace.text = trace),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
