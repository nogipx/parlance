/// switchboard-mcp: a switchboard for agents over stdio (SPEC §16).
///
/// It connects to a host's registry over remote (a Unix socket, or TCP on a
/// network you trust) and serves the curated MCP tools on stdin and stdout.
/// What the agent may do is the host's to say: the session's principal.
///
///   switchboard-mcp --connect unix:/path/to/registry.sock [--command-tools]
///   switchboard-mcp --connect tcp://127.0.0.1:7000
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:rpc_dart/rpc_dart.dart';
import 'package:rpc_dart_socket/rpc_dart_socket.dart';
import 'package:switchboard/mcp.dart';
import 'package:switchboard/remote.dart';

const _usage = '''
usage: switchboard-mcp --connect <unix:/path | tcp://host:port> [options]

  --connect <address>   the host's registry
  --command-tools       a tool for each command too, besides the curated ones
  --name <name>         the server's name, as the agent's client shows it
''';

Future<void> main(List<String> args) async {
  String? connect;
  var commandTools = false;
  var name = 'switchboard';
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--connect' when i + 1 < args.length:
        connect = args[++i];
      case '--command-tools':
        commandTools = true;
      case '--name' when i + 1 < args.length:
        name = args[++i];
      case '-h' || '--help':
        stdout.write(_usage);
        return;
      default:
        stderr.write('unknown argument ${args[i]}\n$_usage');
        exitCode = 64;
        return;
    }
  }
  final address = connect == null ? null : parseAddress(connect);
  if (address == null) {
    stderr.write(_usage);
    exitCode = 64;
    return;
  }

  final connection = RpcClientConnection(
    transportFactory: (cancel) =>
        connectRpcSocket(address, cancellationToken: cancel),
  );
  connection.connect();
  final endpoint = RpcCallerEndpoint(transport: connection.transport);
  final client = SwitchboardClient(endpoint);
  final mirror = RegistryMirror()..follow(client);
  // The feed ends when the host goes; follow it again until it is back.
  final refollow = Timer.periodic(const Duration(seconds: 2), (_) {
    if (!mirror.synced) mirror.follow(client);
  });
  final board = RemoteBoard(client, mirror);

  late final McpSession session;
  session = McpSession(
    input: stdin.transform(utf8.decoder).transform(const LineSplitter()),
    output: stdout.writeln,
    name: name,
    instructions: switchboardInstructions,
    log: stderr.writeln,
    tools: () async {
      try {
        return await switchboardTools(board, commandTools: commandTools);
      } on Object catch (e) {
        stderr.writeln('switchboard-mcp: the host is not reachable: $e');
        return const [];
      }
    },
  );
  final changes = board.catalogChanges.listen((_) => session.toolsChanged());

  await session.done;
  refollow.cancel();
  await changes.cancel();
  await mirror.dispose();
  await endpoint.close();
  await connection.dispose();
}

/// `unix:/path` or `tcp://host:port`; null for anything else.
RpcSocketAddress? parseAddress(String s) {
  if (s.startsWith('unix:')) return RpcSocketAddress.unix(s.substring(5));
  final tcp = RegExp(r'^tcp://([^:]+):(\d+)$').firstMatch(s);
  if (tcp != null) {
    return RpcSocketAddress.tcp(tcp[1]!, int.parse(tcp[2]!));
  }
  return null;
}
