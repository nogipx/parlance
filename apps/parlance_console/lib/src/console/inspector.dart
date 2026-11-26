import 'dart:convert';

import 'package:material_ui/material_ui.dart';

import 'client.dart';

typedef _Word = ({
  String address,
  String kind,
  String status,
  String? why,
  Object? params,
});

class Inspector extends StatefulWidget {
  const Inspector({super.key, required this.client, required this.prefix});
  final ConsoleClient client;
  final String prefix;
  @override
  State<Inspector> createState() => _InspectorState();
}

class _InspectorState extends State<Inspector> {
  List<_Word> _words = [];
  _Word? _word;
  final _params = TextEditingController(text: '{}');
  String _result = '', _search = '';
  Set<String> _actions = {};
  bool _loading = true, _running = false;
  int _request = 0;
  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final c = widget.client;
      final description = await c.call('${widget.prefix}_describe');
      final tools = (await c.request('tools/list'))['tools'] as List<dynamic>;
      final catalog = jsonDecode(
        ConsoleClient.resultText(description),
      ) as Map<String, dynamic>;
      final prefix = '${widget.prefix}_';
      final actions = tools
          .cast<Map<String, dynamic>>()
          .map((t) => t['name'] as String)
          .where((name) => name.startsWith(prefix))
          .map((name) => name.substring(prefix.length))
          .toSet();
      final described = <String, _Word>{};
      for (final (group, kind) in [
        ('states', 'state'),
        ('facts', 'fact'),
        ('commands', 'command'),
      ]) {
        for (final item
            in (catalog[group] as List).cast<Map<String, dynamic>>()) {
          final address = item['name'] as String;
          described[address] = (
            address: address,
            kind: item['query'] == true ? 'query' : kind,
            status: item['unavailable'] == null ? 'ready' : 'unavailable',
            why: item['unavailable'] as String?,
            params: item['params'],
          );
        }
      }
      List<_Word> words;
      if (actions.contains('targets')) {
        final targets = jsonDecode(
          ConsoleClient.resultText(await c.call('${prefix}targets')),
        ) as List;
        words = [
          for (final target in targets.cast<Map<String, dynamic>>())
            for (final vocabulary
                in (target['vocabularies'] as List)
                    .cast<Map<String, dynamic>>())
              for (final word
                  in (vocabulary['words'] as List).cast<Map<String, dynamic>>())
                (
                  address: word['address'] as String,
                  kind: word['is'] as String,
                  status: word['status'] as String,
                  why: word['why'] as String?,
                  params: described[word['address']]?.params ?? word['params'],
                ),
        ];
      } else {
        words = described.values.toList();
      }
      if (mounted) {
        setState(() {
          _words = words;
          _word = null;
          _result = '';
          _actions = actions;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _result = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _run(String tool) async {
    final word = _word;
    if (word == null || _running) return;
    final request = ++_request;
    setState(() => _running = true);
    try {
      final name = word.address;
      final args = switch (tool) {
        'call' => <String, Object?>{
          'command': name,
          'params': jsonDecode(_params.text) as Map<String, dynamic>,
        },
        'recent_facts' => <String, Object?>{'fact': name},
        _ => <String, Object?>{'state': name},
      };
      final result = await widget.client.call('${widget.prefix}_$tool', args);
      if (mounted && request == _request) {
        setState(() => _result = ConsoleClient.resultText(result));
      }
    } catch (e) {
      if (mounted && request == _request) {
        setState(() => _result = e.toString());
      }
    } finally {
      if (mounted && request == _request) setState(() => _running = false);
    }
  }

  @override
  void dispose() {
    _params.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = _word;
    final visible = _words
        .where((w) => w.address.toLowerCase().contains(_search))
        .toList();
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(labelText: 'Find a word'),
                  onChanged: (s) => setState(() => _search = s.toLowerCase()),
                ),
              ),
              Text(
                _search.isEmpty
                    ? '${_words.length} words'
                    : '${visible.length} / ${_words.length} words',
              ),
              IconButton(
                tooltip: 'Refresh catalog',
                onPressed: _loading || _running ? null : _refresh,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: ListView.builder(
                    itemCount: visible.length,
                    itemBuilder: (context, i) {
                      final w = visible[i];
                      return ListTile(
                        dense: true,
                        title: Text(w.address),
                        subtitle: Text(
                          w.status == 'ready'
                              ? w.kind
                              : '${w.kind} · ${w.status == 'notPermitted' ? 'Not permitted' : w.status}',
                        ),
                        selected: w == selected,
                        onTap: () => setState(() {
                          _request++;
                          _running = false;
                          _word = w;
                          _result = '';
                          _params.text = '{}';
                        }),
                      );
                    },
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(8),
                    children: [
                      if (selected != null) ...[
                        SelectableText(selected.address),
                        if (selected.why case final why?) SelectableText(why),
                        if (selected.kind == 'command' ||
                            selected.kind == 'query') ...[
                          SelectableText(
                            const JsonEncoder.withIndent('  ')
                                .convert(selected.params),
                          ),
                          if (selected.status == 'ready' &&
                              _actions.contains('call'))
                            TextField(
                              controller: _params,
                              decoration: const InputDecoration(
                                labelText: 'Parameters (JSON)',
                              ),
                              maxLines: null,
                            ),
                        ],
                        Wrap(
                          spacing: 6,
                          children: [
                            if (selected.status == 'ready')
                              for (final action in switch (selected.kind) {
                                'state' => ['read', 'why'],
                                'fact' => ['recent_facts'],
                                'query' || 'command' => ['call'],
                                _ => <String>[],
                              })
                                if (_actions.contains(action))
                                  OutlinedButton(
                                    onPressed: _running
                                        ? null
                                        : () => _run(action),
                                    child: Text(action),
                                  ),
                          ],
                        ),
                      ],
                      if (_result.isNotEmpty)
                        SelectableText(
                          _result,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
