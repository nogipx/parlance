import 'package:rpc_dart/rpc_dart.dart';
import 'package:rpc_dart_log/rpc_dart_log_server.dart';

import 'host_logs.dart';

/// The two unary methods spoken by LogCollectorOutput. A responder per
/// connection keeps its handshake and record acknowledgements on that peer.
final class LogIngress extends RpcResponderContract {
  LogIngress(this.id, this.sessions, this.buffer)
    : super('LogCollectorService');

  final int id;
  final Map<int, LogCollectorSession> sessions;
  final LogCollectorMcpBuffer buffer;
  static const _codec = RpcCodec<_Message>(_Message.new);

  @override
  void setup() {
    addUnaryMethod(
      methodName: 'handshake',
      handler: _handshake,
      requestCodec: _codec,
      responseCodec: _codec,
    );
    addUnaryMethod(
      methodName: 'send',
      handler: _record,
      requestCodec: _codec,
      responseCodec: _codec,
    );
  }

  Future<_Message> _handshake(_Message message, {RpcContext? context}) async {
    sessions.putIfAbsent(
      id,
      () => LogCollectorSession(
        id: id,
        deviceName: message.fields['deviceName'] as String? ?? 'unknown',
        app: message.fields['app'] as String? ?? 'unknown',
      ),
    );
    return _Message({'sessionId': id});
  }

  Future<_Message> _record(_Message message, {RpcContext? context}) async {
    _store(buffer, sessions[id]?.label ?? 'unknown', message.fields);
    return const _Message({});
  }
}

void _store(
  LogCollectorMcpBuffer buffer,
  String device,
  Map<String, dynamic> fields,
) {
  final record = switch (fields['type']) {
    'event' => LogEvent.fromJson(fields),
    'span' => LogSpan.fromJson(fields),
    _ => null,
  };
  if (record != null) {
    buffer.addRecord(TaggedRecord(deviceLabel: device, record: record));
  }
}

/// Sessions retry an unacknowledged batch when reconnecting. Keep the last
/// accepted sequence for recent device instances independently of their socket.
final class HostLogIngress extends RpcResponderContract {
  HostLogIngress(this.session, this.buffer, this.cursors)
    : super('CollectorLogs');
  final LogCollectorSession session;
  final LogCollectorMcpBuffer buffer;
  final Map<(String, String), int> cursors;

  @override
  void setup() {
    addUnaryMethod(
      methodName: 'append',
      requestCodec: LogBatch.codec,
      responseCodec: LogBatch.codec,
      handler: _append,
    );
  }

  Future<LogBatch> _append(LogBatch batch, {RpcContext? context}) async {
    final first = batch.fields['first'] as int;
    final records = batch.fields['records'] as List;
    if (first < 1 || records.isEmpty || records.length > LogBatch.limit) {
      throw const FormatException('Invalid log batch');
    }
    final key = (session.app, session.label);
    final previous = cursors[key] ?? 0;
    for (var i = 0; i < records.length; i++) {
      if (first + i <= previous) continue;
      _store(
        buffer,
        session.label,
        (records[i] as Map).cast<String, dynamic>(),
      );
      cursors.remove(key);
      cursors[key] = first + i;
    }
    if (cursors.length > 2048) cursors.remove(cursors.keys.first);
    return LogBatch({});
  }
}

final class _Message implements IRpcSerializable {
  const _Message(this.fields);
  final Map<String, dynamic> fields;
  @override
  Map<String, dynamic> toJson() => fields;
}
