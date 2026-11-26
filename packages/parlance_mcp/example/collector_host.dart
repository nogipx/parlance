/// Start the collector first, then run `dart run example/collector_host.dart`.
library;

import 'package:parlance/app.dart';
import 'package:parlance_mcp/collector_host.dart';
import 'package:rpc_dart/logger.dart';

import 'notes.dart';

Future<void> main() async {
  final logs = LogController(outputs: []);
  final host = Host(log: logs.scope('notes'));
  host.participant(const Principal('notes'), owners: [Book()]);
  final diagnostics = CollectorHost(
    host: host,
    logs: logs,
    principal: const Principal('diagnostics'),
    app: 'Notes',
    device: 'example',
    address: Uri.parse(
      const String.fromEnvironment(
        'COLLECTOR_HOST',
        defaultValue: 'ws://127.0.0.1:9502',
      ),
    ),
    logAddress: Uri.parse(
      const String.fromEnvironment(
        'COLLECTOR_LOG',
        defaultValue: 'ws://127.0.0.1:9500',
      ),
    ),
  );
  logs.scope('notes').info('Notes host ready');
  try {
    await diagnostics.done;
  } finally {
    await host.dispose();
    logs.dispose();
  }
}
