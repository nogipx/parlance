import 'dart:async';
import 'dart:convert';

import 'package:material_ui/material_ui.dart';

import '../look.dart';
import 'client.dart';

/// Older collectors can read recent facts, including from hosts which keep
/// their full journal private. Only fetch the selected word while visible.
class LiveFacts extends StatefulWidget {
  const LiveFacts({
    super.key,
    required this.client,
    required this.prefix,
    required this.active,
  });
  final ConsoleClient client;
  final String prefix;
  final bool active;
  @override
  State<LiveFacts> createState() => _LiveFactsState();
}

class _LiveFactsState extends State<LiveFacts> {
  Timer? _timer;
  List<String>? _words;
  String? _word, _error;
  List<Map<String, dynamic>> _facts = [];
  bool _busy = false;
  int _revision = -1;
  @override
  void initState() {
    super.initState();
    unawaited(_poll());
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_poll()),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    if (_busy || !widget.active) return;
    _busy = true;
    try {
      final client = widget.client;
      final prefix = widget.prefix;
      final rev = client.catalogRevision;
      if (_words == null || rev != _revision) {
        final result = await client.call('${prefix}_describe');
        final catalog = jsonDecode(
          ConsoleClient.resultText(result),
        ) as Map<String, dynamic>;
        final words =
            (catalog['facts'] as List<dynamic>)
                .cast<Map<String, dynamic>>()
                .map((d) => d['name'] as String)
                .toList()
              ..sort();
        if (!mounted) return;
        setState(() {
          _revision = rev;
          _words = words;
          if (!words.contains(_word)) {
            _word = words.firstOrNull;
            _facts = [];
          }
        });
      }
      final word = _word;
      if (word == null) return;
      final result = await client.call('${prefix}_recent_facts', {
        'fact': word,
        'count': 50,
      });
      if (!mounted || _word != word || !widget.active) return;
      setState(() {
        _error = null;
        _facts = (jsonDecode(ConsoleClient.resultText(result)) as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .reversed
            .toList();
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Live facts',
          style: TextStyle(color: Look.fact, fontWeight: FontWeight.bold),
        ),
        if (_words?.isNotEmpty == true)
          DropdownButton<String>(
            isExpanded: true,
            value: _word,
            items: [
              for (final word in _words!)
                DropdownMenuItem(
                  value: word,
                  child: Text(word, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) {
              setState(() {
                _word = v;
                _facts = [];
                _error = null;
              });
              unawaited(_poll());
            },
          ),
        if (_error != null) SelectableText(_error!),
        if (_words?.isEmpty == true)
          const Text('No facts published by this host'),
        if (_word != null && _facts.isEmpty && _error == null)
          const Text('Waiting for facts…'),
        Expanded(
          child: ListView.builder(
            itemCount: _facts.length,
            itemBuilder: (context, i) {
              final fact = _facts[i];
              return ListTile(
                leading: const Icon(Icons.bolt, color: Look.fact),
                title: SelectableText(
                  jsonEncode(fact['payload']),
                  style: Look.mono,
                ),
                subtitle: Text("${fact['at']}   ${fact['by']}"),
              );
            },
          ),
        ),
      ],
    ),
  );
}
