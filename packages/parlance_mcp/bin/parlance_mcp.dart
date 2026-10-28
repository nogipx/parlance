/// parlance-mcp: a parlance for agents over stdio (SPEC §16).
///
/// It connects to a host's registry over remote (a Unix socket, or TCP on a
/// network you trust) and serves the curated MCP tools on stdin and stdout.
/// What the agent may do is the host's to say: the session's principal.
///
///   parlance-mcp --connect unix:/path/to/registry.sock [--command-tools]
///   parlance-mcp --connect tcp://127.0.0.1:7000
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:rpc_dart/rpc_dart.dart';
import 'package:rpc_dart_socket/rpc_dart_socket.dart';
import 'package:parlance/mcp.dart';
import 'package:parlance/remote.dart';

const _usage = '''
usage: parlance-mcp --connect <unix:/path | tcp://host:port> [options]

  --connect <address>   the host's registry
  --command-tools       a tool for each command too, besides the curated ones
  --name <name>         the server's name, as the agent's client shows it
''';

Future<void> main(List<String> args) async {
  String? connect;
  var commandTools = false;
  var name = 'parlance';
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
  // The agent is a participant of the host's: it joins, and joins again
  // whenever the host is back.
  final joining = RemoteParticipant.join(connection);
  RemoteParticipant? joined;
  StreamSubscription<void>? changes;

  late final McpSession session;
  session = McpSession(
    input: stdin.transform(utf8.decoder).transform(const LineSplitter()),
    output: stdout.writeln,
    name: name,
    instructions: parlanceInstructions,
    log: stderr.writeln,
    tools: () async {
      try {
        final p = await joining.timeout(const Duration(seconds: 5));
        return await parlanceTools(p, commandTools: commandTools);
      } on Object catch (e) {
        stderr.writeln('parlance-mcp: the host is not reachable: $e');
        return const [];
      }
    },
  );
  unawaited(
    joining.then((p) {
      joined = p;
      changes = p.catalogChanges.listen((_) => session.toolsChanged());
    }, onError: (Object e) => stderr.writeln('parlance-mcp: $e')),
  );

  await session.done;
  await changes?.cancel();
  await joined?.close();
  await connection.dispose();
}

RpcSocketAddress? parseAddress(String s) {
  if (s.startsWith('unix:')) return RpcSocketAddress.unix(s.substring(5));
  final tcp = RegExp(r'^tcp://([^:]+):(\d+)$').firstMatch(s);
  if (tcp != null) {
    return RpcSocketAddress.tcp(tcp[1]!, int.parse(tcp[2]!));
  }
  return null;
}
