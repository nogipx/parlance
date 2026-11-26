# Changelog

## 0.5.0

- Upgrade the collector before updating hosts. New hosts share logs, inspection and optional journal pages over one WebSocket with one reconnect loop. The collector also accepts 0.4.x hosts and standalone `rpc_dart_log` clients.
- Disconnecting detaches the log output immediately. During network outages the host retains recent logs and resends unacknowledged batches after reconnecting.

## 0.4.1

- Desktop tools can attach to a local collector or start one with `LocalCollector.open`. `CollectorLan` forwards WebSocket and TLS connections from devices on the local network.
- Hosts can opt into sharing a bounded, metadata-only journal with `CollectorHost(shareJournal: true)`. Clients can follow entries by cursor and detect gaps.
- `rpc_log_sources` now returns device names and the log cursor as structured content for live log viewers.

## 0.4.0

- Breaking: the executable now starts a collector. Replace `--connect` with an outbound `CollectorHost` in each app and point the agent at the collector's Unix socket.
- Accept host registries and existing `rpc_dart_log` clients on one WebSocket port. Inspect multiple hosts and query their buffered logs from one MCP connection on macOS or Linux. Hosts can opt in to command tools for their served principal.
- Connect Dart hosts with `CollectorHost`. It streams their logs, reconnects after a disconnect, and associates each live host with its log source.
- Requires Dart 3.10.1 or later.

## 0.3.0

- Require parlance 0.4.0 and its current RPC contract.
- Remove renamed-word aliases from tool catalogs; support only MCP protocol 2025-06-18.

## 0.2.0

- Extend `why` with call inspection and bounded state history, mixed causal messages and explicit evidence gaps.
- Return caller IDs in `structuredContent.call`, including automatically generated IDs, for later inspection.

- Require parlance 0.3.0.

- Breaking: group targets tool publications by vocabulary and use the shared name-based discovery filters.

- Require rpc_dart 7.2.0.

- Reflect live host access policy in command discovery, state reads and calls; preserve warn metadata while the host records actual accesses.

- Add target discovery and full target/word addresses in tool metadata and calls. Encode command tool names without punctuation or target collisions.

- Breaking: remove the entity directory from `describe` and dynamic choices
  from JSON Schema generation. Domain catalogs use ordinary states or queries;
  static enums continue to expose their values.

## 0.1.2

- Support parlance 0.2.0 and its generator.

## 0.1.1

- Fix the link to the packaged parlance-core contract documentation.

## 0.1.0

- First published release: the `parlance-mcp` server speaking a host's
  parlance to agents over stdio, over a Unix socket or TCP.
