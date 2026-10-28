/// Guests in this process, each over a connection of its own in memory, as
/// its WASM would be over the one its runtime gives it: for the demo and
/// its test.
library;

import 'package:rpc_dart/rpc_dart.dart';

import 'host.dart';

/// The endpoints opened, to close at the end.
final List<RpcPeerEndpoint> _opened = [];

/// Loads the guest [id] into [host] and starts it ([start], what its
/// `main` does with the endpoint it is handed).
Future<T> loadInMemory<T>(
  Host host,
  String id,
  Future<T> Function(RpcPeerEndpoint endpoint) start,
) async {
  final (guest, hosted) = RpcChannelTransport.memoryPair();
  final side = RpcPeerEndpoint(transport: hosted);
  host.load(id, side);
  side.start();
  final own = RpcPeerEndpoint(transport: guest)..start();
  _opened.addAll([side, own]);
  return start(own);
}

/// Closes every endpoint [loadInMemory] opened.
Future<void> closeInMemory() async {
  for (final e in _opened) {
    await e.close();
  }
  _opened.clear();
}
