import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'protocol.dart';

/// MCP for agents on this machine only, on a Unix socket (SPEC §16): each
/// connection is one [McpSession]. An agent's client runs `nc -U <path>`
/// (or a bridge) as its stdio server.
///
/// The socket is made readable and writable by its owner alone.
final class McpSocketServer {
  McpSocketServer({
    required this.path,
    required this.tools,
    this.name = 'parlance',
    this.instructions,
    this.log,
    this.onSessions,
  });

  /// The socket's path; a file left there is replaced.
  final String path;

  /// The tools there are now, as each session asks for them.
  final FutureOr<List<McpTool>> Function() tools;

  /// The server's name, as `initialize` tells it.
  final String name;

  /// What an agent is told when it connects: what the host is, how to work.
  final String? instructions;
  final void Function(String line)? log;

  /// How many agents are connected, when that changes.
  final void Function(int count)? onSessions;

  ServerSocket? _server;
  final Map<Socket, McpSession> _sessions = {};

  /// How many agents are connected now.
  int get sessions => _sessions.length;

  Future<void> start() async {
    if (_server != null) throw StateError('already listening on $path');
    final file = File(path);
    if (file.existsSync()) file.deleteSync();
    final server = _server = await ServerSocket.bind(
      InternetAddress(path, type: InternetAddressType.unix),
      0,
    );
    final chmod = await Process.run('chmod', ['600', path]);
    if (chmod.exitCode != 0) {
      // A socket others may reach is not served.
      await server.close();
      _server = null;
      throw FileSystemException('cannot make it its owner\'s alone', path);
    }
    server.listen(_serve, onError: (Object e) => log?.call('mcp: $e'));
    log?.call('mcp: listening on $path');
  }

  void _serve(Socket socket) {
    final session = McpSession(
      input: utf8.decoder.bind(socket).transform(const LineSplitter()),
      output: (line) => socket.write('$line\n'),
      tools: tools,
      name: name,
      instructions: instructions,
      log: log,
    );
    _sessions[socket] = session;
    onSessions?.call(_sessions.length);
    log?.call('mcp: connected');
    unawaited(session.done.whenComplete(() => _close(socket)));
    // What is written to an agent gone (the pipe broken) fails here, and
    // ends its session: not the host, as an error no one heard would.
    unawaited(
      socket.done
          .then<void>((_) {}, onError: (Object e) => log?.call('mcp: $e'))
          .whenComplete(() => _close(socket)),
    );
  }

  /// The tools are others now: every agent connected lists them again.
  void toolsChanged() {
    for (final s in _sessions.values) {
      s.toolsChanged();
    }
  }

  void _close(Socket socket) {
    final session = _sessions.remove(socket);
    if (session == null) return;
    unawaited(session.close());
    socket.destroy();
    onSessions?.call(_sessions.length);
    log?.call('mcp: disconnected');
  }

  /// Ends every session and removes the socket.
  Future<void> stop() async {
    for (final s in [..._sessions.keys]) {
      _close(s);
    }
    await _server?.close();
    _server = null;
    final file = File(path);
    if (file.existsSync()) file.deleteSync();
  }
}
