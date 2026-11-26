import 'dart:async';
import 'dart:collection';

import 'package:rpc_dart/rpc_dart.dart';

final class LogBatch implements IRpcSerializable {
  LogBatch(this.fields);
  final Map<String, dynamic> fields;
  static const codec = RpcCodec<LogBatch>(LogBatch.new);
  static const limit = 32;
  @override
  Map<String, dynamic> toJson() => fields;
}

/// One acknowledged batch at a time on the host's existing peer. Records
/// remain queued across disconnects, including the outstanding batch.
final class HostLogs extends LogOutput {
  final _records =
      Queue<({int sequence, int bytes, Map<String, dynamic> fields})>();
  var _sequence = 0, _bytes = 0;
  RpcPeerEndpoint? _peer;
  Completer<void>? _waiting;

  @override
  void write(LogRecord record) {
    final fields = switch (record) {
      LogEvent() => record.toJson(),
      LogSpan() => record.toJson(),
      LogSpanStart() => null,
    };
    if (fields == null) return;
    final size = approxJsonBytes(fields);
    // A large record travels alone. Discard it only if it cannot fit in an
    // RPC message, otherwise a rejected record would force endless retries.
    final wireLimit = const RpcSecurityPolicy().maxMessageLengthBytes;
    if (size >= wireLimit ~/ 4) {
      final single = LogBatch({
        'first': _sequence + 1,
        'records': [fields],
      });
      if (LogBatch.codec.serialize(single).length > wireLimit) return;
    }
    _records.add((sequence: ++_sequence, bytes: size, fields: fields));
    _bytes += size;
    while (_records.length > 2000 ||
        (_records.length > 1 && _bytes > 8 << 20)) {
      _bytes -= _records.removeFirst().bytes;
    }
    _wake();
  }

  void _wake() {
    _waiting?.complete();
    _waiting = null;
  }

  Future<void> sendOn(RpcPeerEndpoint peer) async {
    _peer = peer;
    while (identical(peer, _peer)) {
      if (_records.isEmpty) {
        _waiting = Completer<void>();
        await _waiting!.future;
        continue;
      }
      final first = _records.first.sequence;
      final items = <Map<String, dynamic>>[];
      var bytes = 0;
      for (final record in _records) {
        if (items.isNotEmpty && bytes + record.bytes > 128 << 10) break;
        items.add(record.fields);
        bytes += record.bytes;
        if (items.length == LogBatch.limit) break;
      }
      await peer.unary<LogBatch, LogBatch>(
        serviceName: 'CollectorLogs',
        methodName: 'append',
        request: LogBatch({'first': first, 'records': items}),
        requestCodec: LogBatch.codec,
        responseCodec: LogBatch.codec,
        context: RpcContext.empty().withTimeout(const Duration(seconds: 15)),
      );
      if (!identical(peer, _peer)) return;
      final last = first + items.length - 1;
      while (_records.isNotEmpty && _records.first.sequence <= last) {
        _bytes -= _records.removeFirst().bytes;
      }
    }
  }

  void disconnect() {
    _peer = null;
    _wake();
  }

  @override
  void dispose() {
    disconnect();
    _records.clear();
    _bytes = 0;
  }
}
