import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:parlance/tools.dart';
import 'package:parlance_mcp/io.dart';
import 'package:parlance_mcp/parlance_mcp.dart';
import 'package:rpc_dart/rpc_dart.dart';
import 'package:rpc_dart_log/rpc_dart_log_server.dart';
import 'package:rpc_dart_websocket/io.dart';
import 'package:rpc_dart_websocket/rpc_dart_websocket.dart';

import 'log_tools.dart';

/// One process owns the log buffer and connected hosts across agent sessions.
final class Collector {
  Collector({
    required String socket,
    required this.bind,
    required this.hostPort,
    required int logPort,
  }) : logs = LogCollectorServer(host: bind, port: logPort) {
    agents = McpSocketServer(
      path: socket,
      replaceExisting: false,
      tools: _tools,
      instructions:
          'List hosts for their tool prefixes and device labels. '
          'Use rpc_log_sources and rpc_log_get_logs for buffered logs.',
    );
  }

  final String bind;
  final int hostPort;
  final LogCollectorServer logs;
  final _buffer = LogCollectorMcpBuffer();
  late final McpSocketServer agents;
  HttpServer? _hosts;
  bool _servingAgents = false;
  bool _stopping = false;
  final _connections = <WebSocket>{};
  final _tasks = <Future<void>>{};
  final _live = <String, _HostTools>{};
  int _next = 0;

  int get boundHostPort => _hosts!.port;

  Future<void> start() async {
    logs.onRecord.listen(_buffer.addRecord);
    try {
      await logs.start();
      _hosts = await HttpServer.bind(bind, hostPort);
      await agents.start();
      _servingAgents = true;
      _hosts!.listen((request) {
        final work = _accept(request).catchError((Object error) {
          if (!_stopping) {
            stderr.writeln('parlance-mcp: host disconnected: $error');
          }
        });
        _tasks.add(work);
        unawaited(work.whenComplete(() => _tasks.remove(work)));
      });
    } on Object {
      await stop();
      rethrow;
    }
  }

  Future<void> _accept(HttpRequest request) async {
    final app = request.uri.queryParameters['app'];
    final device = request.uri.queryParameters['device'];
    final commands = request.uri.queryParameters['commandTools'] == 'true';
    if (!WebSocketTransformer.isUpgradeRequest(request) ||
        app == null ||
        app.trim().isEmpty ||
        device == null ||
        device.trim().isEmpty) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }
    final socket = await WebSocketTransformer.upgrade(
      request,
      compression: CompressionOptions.compressionOff,
    );
    if (_stopping) {
      await socket.close();
      return;
    }
    _connections.add(socket);
    final id = 'h${++_next}';
    final peer = RpcPeerEndpoint(
      transport: RpcWebSocketResponderTransport(rpcWebSocketChannel(socket)),
    );
    RemoteParticipant? participant;
    StreamSubscription<void>? changes;
    try {
      peer.start();
      var expired = false;
      final observer = participant = await RemoteParticipant.joinEndpoint(peer)
          .then((p) async {
            if (expired) await p.dispose();
            return p;
          })
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              expired = true;
              throw TimeoutException('host did not register');
            },
          );
      final host = _HostTools(app, device);
      _live[id] = host;
      Future<void> refresh() async {
        final revision = ++host.revision;
        try {
          final tools = await parlanceTools(
            observer,
            commandTools: commands,
          ).timeout(const Duration(seconds: 5));
          if (_live[id] != host || revision != host.revision) return;
          host.tools = [
            for (final t in tools)
              if ('${id}_${t.name}'.length <= 64 &&
                  (commands ||
                      const {
                        'targets',
                        'describe',
                        'why',
                        'read',
                        'recent_facts',
                      }.contains(t.name)))
                McpTool(
                  name: '${id}_${t.name}',
                  description: t.description,
                  properties: t.properties,
                  required: t.required,
                  run: (args) => _live[id] == host
                      ? t.run(args)
                      : Future.value(
                          const McpResult.error(
                            'Host disconnected. List hosts again.',
                          ),
                        ),
                ),
          ];
          agents.toolsChanged();
        } on Object {
          // Retry a failed catalog read through the host connector.
          if (_live[id] == host && revision == host.revision) {
            await socket.close();
          }
        }
      }

      changes = observer.catalogChanges.listen((_) => unawaited(refresh()));
      await refresh();
      await socket.done;
    } finally {
      if (_live.remove(id) != null) agents.toolsChanged();
      await changes?.cancel();
      await participant?.dispose();
      await peer.close();
      _connections.remove(socket);
      await socket.close();
    }
  }

  List<McpTool> _tools() {
    return [
      McpTool(
        name: 'hosts',
        description:
            'Connected Parlance hosts. Use the tool prefix for this session and the device label for log queries.',
        run: (_) async => McpResult.json([
          for (final entry in _live.entries)
            {
              'prefix': entry.key,
              'app': entry.value.app,
              'device': entry.value.device,
            },
        ]),
      ),
      ...logTools(logs, _buffer),
      for (final host in _live.values) ...host.tools,
    ];
  }

  Future<void> stop() async {
    _stopping = true;
    await _hosts?.close(force: true);
    for (final socket in _connections.toList()) {
      await socket.close();
    }
    await Future.wait(_tasks.toList());
    if (_servingAgents) await agents.stop();
    await logs.stop();
  }
}

final class _HostTools {
  _HostTools(this.app, this.device);
  final String app;
  final String device;
  int revision = 0;
  List<McpTool> tools = [];
}

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
    ..addOption('host-port', defaultsTo: '9502')
    ..addOption('log-port', defaultsTo: '9500')
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
      hostPort: port('host-port'),
      logPort: port('log-port'),
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
      'parlance-mcp: hosts ws://${collector.bind}:${collector.boundHostPort}, '
      'logs ws://${collector.bind}:${collector.logs.boundPort}, MCP ${collector.agents.path}',
    );
    await stopped.future;
    await collector.stop();
  } finally {
    for (final sub in signals) {
      await sub.cancel();
    }
  }
}
