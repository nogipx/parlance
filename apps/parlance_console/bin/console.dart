import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:parlance_mcp/io.dart';

import 'wifi.dart';

/// Runs the native window with MCP on inherited pipes.
Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('Usage: dart run bin/console.dart <console executable>');
    exitCode = 64;
    return;
  }
  final directory = '${Platform.environment['HOME']!}/.parlance';
  final mkdir = await Process.run('/bin/mkdir', ['-p', '-m', '700', directory]);
  if (mkdir.exitCode != 0) {
    throw FileSystemException('${mkdir.stderr}', directory);
  }
  final path = '$directory/mcp.sock';
  final collector = await LocalCollector.open(path);
  final wifi = ConsoleWifi(Directory(directory));
  try {
    await wifi.restore();
    final window = await Process.start(
      args.single,
      [],
      environment: {'PARLANCE_CONSOLE_STDIO': '1'},
    );
    final signals = [
      for (final signal in [ProcessSignal.sigint, ProcessSignal.sigterm])
        signal.watch().listen((_) => window.kill()),
    ];
    // The collector also writes to stderr while the window is running.
    final errors = window.stderr.forEach(stderr.add);
    var connected = true;
    final requests = utf8.decoder
        .bind(window.stdout)
        .transform(const LineSplitter())
        .asyncMap((line) async {
          if (!connected || !line.startsWith('{')) return;
          final message = jsonDecode(line) as Map<String, dynamic>;
          if (message['method'] == 'console/wifi') {
            if (message['params'] case {'enabled': final bool enabled}) {
              await wifi.setEnabled(enabled);
            }
            if (!connected) {
              await wifi.close();
              return;
            }
            window.stdin.writeln(
              jsonEncode({
                'jsonrpc': '2.0',
                'id': message['id'],
                'result': wifi.status,
              }),
            );
          } else {
            collector.socket.writeln(line);
          }
        })
        .drain<void>();
    // EOF lets the window show that its collector has gone away.
    final replies = utf8.decoder
        .bind(collector.socket)
        .transform(const LineSplitter())
        .listen(
          window.stdin.writeln,
          onDone: () {
            connected = false;
            unawaited(wifi.close());
            unawaited(window.stdin.close());
          },
        );
    unawaited(window.stdin.done.then<void>((_) {}, onError: (Object _) {}));
    try {
      exitCode = await window.exitCode;
    } finally {
      connected = false;
      for (final subscription in signals) {
        await subscription.cancel();
      }
      await requests;
      collector.socket.destroy();
      await replies.cancel();
      await errors;
    }
  } finally {
    await wifi.close();
    await collector.close();
  }
}
