import 'dart:async';
import 'dart:io';

/// Forwards host WebSocket connections on a LAN interface to a local collector.
/// The private MCP socket remains independent of both listeners.
final class CollectorLan {
  CollectorLan._(this._plain, this._secure, this._collectorPort) {
    for (final server in <Stream<Socket>>[_plain, ?_secure]) {
      server.listen(
        _forward,
        onError: (Object _) {
          // A failed TLS handshake affects only the connecting client.
        },
      );
    }
  }

  final ServerSocket _plain;
  final SecureServerSocket? _secure;
  final int _collectorPort;
  final _connections = <Socket>{};
  bool _closed = false;

  Uri get android =>
      Uri(scheme: 'ws', host: _plain.address.address, port: _plain.port);
  Uri? get ios => _secure == null
      ? null
      : Uri(scheme: 'wss', host: _secure.address.address, port: _secure.port);

  static Future<CollectorLan> start(
    InternetAddress address, {
    int collectorPort = 9500,
    int plainPort = 9444,
    int securePort = 9443,
    SecurityContext? tls,
  }) async {
    final plain = await ServerSocket.bind(address, plainPort);
    try {
      final secure = tls == null
          ? null
          : await SecureServerSocket.bind(
              address,
              securePort,
              tls,
              supportedProtocols: ['http/1.1'],
            );
      return CollectorLan._(plain, secure, collectorPort);
    } catch (_) {
      await plain.close();
      rethrow;
    }
  }

  Future<void> _forward(Socket client) async {
    Socket? upstream;
    try {
      if (_closed) return;
      _connections.add(client);
      final peer = upstream = await Socket.connect(
        InternetAddress.loopbackIPv4,
        _collectorPort,
        timeout: const Duration(seconds: 3),
      );
      if (_closed) return;
      _connections.add(peer);
      await Future.any([client.addStream(peer), peer.addStream(client)]);
    } on IOException {
      // Either endpoint may disconnect while bytes are in flight.
    } finally {
      client.destroy();
      upstream?.destroy();
      _connections.remove(client);
      _connections.remove(upstream);
    }
  }

  Future<void> close() async {
    _closed = true;
    for (final socket in _connections.toList()) {
      socket.destroy();
    }
    await Future.wait([_plain.close(), if (_secure != null) _secure.close()]);
  }
}
