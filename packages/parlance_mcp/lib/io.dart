/// MCP over this machine's sockets: [McpSocketServer] serves agents on a
/// Unix socket, a session each. Kept apart from `parlance_mcp.dart`, which
/// needs no `dart:io`.
///
/// The contract: skills/parlance/references/mcp.md (§16).
library;

export 'src/socket_server.dart';
