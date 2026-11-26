@Tags(['process'])
@TestOn('mac-os || linux')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'installed entry point serves diagnostics before any host connects',
    () async {
      final dir = Directory.systemTemp.createTempSync('pmcp');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/agent.sock';
      final process = await Process.start(Platform.resolvedExecutable, [
        'run',
        'bin/parlance_mcp.dart',
        '--socket',
        path,
        '--host-port',
        '0',
        '--log-port',
        '0',
      ]);
      addTearDown(process.kill);
      unawaited(process.stdout.drain<void>());
      final started = Completer<void>();
      process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) {
              if (line.endsWith('MCP $path') && !started.isCompleted) {
                started.complete();
              }
            },
            onDone: () {
              if (!started.isCompleted) {
                started.completeError(
                  StateError('collector exited before startup'),
                );
              }
            },
          );
      await started.future.timeout(const Duration(seconds: 20));
      final socket = await Socket.connect(
        InternetAddress(path, type: InternetAddressType.unix),
        0,
      );
      addTearDown(socket.destroy);
      final lines = StreamIterator(
        utf8.decoder.bind(socket).transform(const LineSplitter()),
      );
      socket.writeln(
        jsonEncode({'jsonrpc': '2.0', 'method': 'initialize', 'id': 1}),
      );
      expect(await lines.moveNext(), isTrue);
      expect(
        jsonDecode(lines.current)['result']['serverInfo']['version'],
        '0.4.0',
      );
      socket.writeln(
        jsonEncode({'jsonrpc': '2.0', 'method': 'tools/list', 'id': 2}),
      );
      expect(await lines.moveNext(), isTrue);
      final tools = jsonDecode(lines.current)['result']['tools'] as List;
      expect(
        tools.map((t) => (t as Map)['name']),
        containsAll(['hosts', 'rpc_log_sources', 'rpc_log_get_logs']),
      );
      socket.destroy();
      await lines.cancel();
      process.kill(ProcessSignal.sigterm);
      expect(await process.exitCode.timeout(const Duration(seconds: 10)), 0);
      expect(FileSystemEntity.typeSync(path), FileSystemEntityType.notFound);
    },
  );
}
