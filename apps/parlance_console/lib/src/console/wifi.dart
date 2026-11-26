import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'client.dart';

class WifiDialog extends StatefulWidget {
  const WifiDialog({super.key, required this.client});
  final ConsoleClient client;

  @override
  State<WifiDialog> createState() => _WifiDialogState();
}

class _WifiDialogState extends State<WifiDialog> {
  bool _enabled = false, _busy = true;
  String? _android, _ios, _error;

  @override
  void initState() {
    super.initState();
    _update();
  }

  Future<void> _update([bool? enabled]) async {
    setState(() => _busy = true);
    try {
      final result = await widget.client.request('console/wifi', {
        'enabled': ?enabled,
      });
      if (!mounted) return;
      setState(() {
        _enabled = result['enabled'] as bool;
        _android = result['android'] as String?;
        _ios = result['ios'] as String?;
        _error = result['error'] as String?;
      });
    } on Object catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Wi-Fi devices'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Accept devices over Wi-Fi'),
              value: _enabled,
              onChanged: _busy ? null : _update,
            ),
            for (final (label, url) in [
              ('Android', _android),
              ('iPhone', _ios),
            ])
              if (url != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(label),
                  subtitle: SelectableText(url),
                  trailing: IconButton(
                    tooltip: 'Copy $label address',
                    icon: const Icon(Icons.copy),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: url));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('$label address copied')),
                        );
                      }
                    },
                  ),
                ),
            if (_ios != null)
              const Text(
                'On iPhone, install and trust the mkcert root certificate once.',
              ),
            if (_error != null) SelectableText(_error!),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  );
}
