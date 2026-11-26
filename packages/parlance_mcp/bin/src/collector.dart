import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:parlance_mcp/io.dart';

Future<void> runCollector(List<String> args) async {
  final parser = ArgParser()
    ..addOption(
      'socket',
      help: 'Local agent Unix socket in a private directory.',
    )
    ..addOption(
      'bind',
      defaultsTo: '127.0.0.1',
      help: 'Host and log ingress address.',
    )
    ..addOption(
      'port',
      defaultsTo: '9500',
      help: 'WebSocket port for both hosts and logs.',
    )
    ..addFlag('help', abbr: 'h', negatable: false);
  late final Collector collector;
  try {
    final parsed = parser.parse(args);
    if (parsed.flag('help')) {
      stdout.writeln(parser.usage);
      return;
    }
    final path = parsed.option('socket');
    if (path == null || path.isEmpty || parsed.rest.isNotEmpty) {
      throw const FormatException('Expected --socket <path>');
    }
    int port(String key) {
      final n = int.tryParse(parsed.option(key)!);
      if (n == null || n < 0 || n > 65535) {
        throw FormatException('Invalid --$key');
      }
      return n;
    }

    collector = Collector(
      socket: path,
      bind: parsed.option('bind')!,
      port: port('port'),
    );
  } on FormatException catch (e) {
    stderr.writeln('${e.message}\n${parser.usage}');
    exitCode = 64;
    return;
  }
  final stopped = Completer<void>();
  final signals = [
    for (final sig in [ProcessSignal.sigint, ProcessSignal.sigterm])
      sig.watch().listen((_) {
        if (!stopped.isCompleted) stopped.complete();
      }),
  ];
  try {
    await collector.start();
    stderr.writeln(
      'parlance-mcp: ${Uri(scheme: 'ws', host: collector.bind, port: collector.boundPort)}, MCP ${collector.agents.path}',
    );
    await stopped.future;
    await collector.stop();
  } finally {
    for (final sub in signals) {
      await sub.cancel();
    }
  }
}
