import 'dart:io';

import 'collector.dart';

/// A local MCP connection, optionally owning the collector it started.
final class LocalCollector {
  LocalCollector._(this.socket, this._owned);

  /// MCP stdio framing over the collector's private Unix socket.
  final Socket socket;
  final Collector? _owned;

  /// Reuse a running service or start one on loopback. The socket parent must exist.
  static Future<LocalCollector> open(String path, {int port = 9500}) async {
    final address = InternetAddress(path, type: InternetAddressType.unix);
    Future<Socket> connect() =>
        Socket.connect(address, 0, timeout: const Duration(seconds: 2));
    try {
      return LocalCollector._(await connect(), null);
    } on SocketException {
      if (await FileSystemEntity.type(path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        rethrow;
      }
    }
    final collector = Collector(socket: path, bind: '127.0.0.1', port: port);
    try {
      await collector.start();
      return LocalCollector._(await connect(), collector);
    } catch (error, stack) {
      await collector.stop();
      // A concurrent launcher can have bound TCP just before binding its socket.
      for (var i = 0; i < 10; i++) {
        try {
          return LocalCollector._(await connect(), null);
        } on SocketException {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      }
      Error.throwWithStackTrace(error, stack);
    }
  }

  /// Detach and stop only a collector started by this connection.
  Future<void> close() async {
    socket.destroy();
    await _owned?.stop();
  }
}
