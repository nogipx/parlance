/// MCP over this machine's sockets: [McpSocketServer] serves agents on a
/// Unix socket, a session each. Kept apart from `mcp.dart`, which needs no
/// `dart:io`.
///
/// The contract: skills/switchboard/references/mcp.md (§16).
library;

export 'src/mcp/socket_server.dart';
