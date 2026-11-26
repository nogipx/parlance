import 'dart:async';
import 'dart:io';

import 'package:parlance/tools.dart';
import 'package:parlance_mcp/parlance_mcp.dart';
import 'package:rpc_dart/rpc_dart.dart';
import 'package:rpc_dart_log/rpc_dart_log_server.dart';
import 'package:rpc_dart_websocket/io.dart';
import 'package:rpc_dart_websocket/rpc_dart_websocket.dart';

import 'log_tools.dart';
import 'log_ingress.dart';
import 'journal_feed.dart';
import 'collector_protocol.dart';
import 'socket_server.dart';

/// One process owns the log buffer and connected hosts across agent sessions.
final class Collector {
  Collector({required String socket, required this.bind, required this.port}) {
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
  final int port;
  final _logSessions = <int, LogCollectorSession>{};
  final _buffer = LogCollectorMcpBuffer();
  late final McpSocketServer agents;
  HttpServer? _hosts;
  bool _servingAgents = false;
  bool _stopping = false;
  final _connections = <WebSocket>{};
  final _tasks = <Future<void>>{};
  final _live = <String, _HostTools>{};
  int _next = 0;

  int get boundPort => _hosts!.port;

  Future<void> start() async {
    try {
      _hosts = await HttpServer.bind(bind, port);
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
    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }
    final socket = await WebSocketTransformer.upgrade(
      request,
      protocolSelector: (offered) => offered.contains(collectorHostProtocol)
          ? collectorHostProtocol
          : null,
      compression: CompressionOptions.compressionOff,
    );
    if (_stopping) {
      await socket.close();
      return;
    }
    _connections.add(socket);
    try {
      final id = ++_next;
      if (socket.protocol == collectorHostProtocol) {
        if (app == null ||
            app.trim().isEmpty ||
            device == null ||
            device.trim().isEmpty) {
          await socket.close(
            WebSocketStatus.policyViolation,
            'Missing app or device',
          );
          return;
        }
        await _serveHost(
          socket,
          'h$id',
          app,
          device,
          commands,
          request.uri.queryParameters['journal'] == 'true',
        );
      } else {
        final peer = RpcResponderEndpoint(
          transport: RpcWebSocketResponderTransport(
            rpcWebSocketChannel(socket),
          ),
        );
        try {
          peer.registerServiceContract(LogIngress(id, _logSessions, _buffer));
          peer.start();
          await socket.done;
        } finally {
          _logSessions.remove(id);
          await peer.close();
        }
      }
    } finally {
      _connections.remove(socket);
      await socket.close();
    }
  }

  Future<void> _serveHost(
    WebSocket socket,
    String id,
    String app,
    String device,
    bool commands,
    bool journal,
  ) async {
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
      final host = _HostTools(app, device, journal ? JournalPeer(peer) : null);
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
            if (host.journal case final feed?)
              McpTool(
                name: '${id}_journal',
                description:
                    'Read a page of live journal JSON lines after a cursor. Dropped entries are reported.',
                properties: const {
                  'after': {'type': 'integer', 'minimum': 0},
                },
                run: (args) async {
                  final after = args['after'] ?? 0;
                  if (after is! int || after < 0) {
                    return const McpResult.error(
                      'Expected a nonnegative cursor',
                    );
                  }
                  if (_live[id] != host) {
                    return const McpResult.error('Host disconnected');
                  }
                  return McpResult.json(await feed.read(after));
                },
              ),
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
              if (entry.value.journal != null) 'journal': true,
            },
        ]),
      ),
      ...logTools(_logSessions.values, _buffer),
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
  }
}

final class _HostTools {
  _HostTools(this.app, this.device, this.journal);
  final JournalPeer? journal;
  final String app;
  final String device;
  int revision = 0;
  List<McpTool> tools = [];
}
