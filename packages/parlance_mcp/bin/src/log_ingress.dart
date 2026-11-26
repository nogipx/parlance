import 'package:rpc_dart/rpc_dart.dart';
import 'package:rpc_dart_log/rpc_dart_log_server.dart';

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
    final fields = message.fields;
    final record = switch (fields['type']) {
      'event' => LogEvent.fromJson(fields),
      'span' => LogSpan.fromJson(fields),
      _ => null,
    };
    if (record != null) {
      buffer.addRecord(
        TaggedRecord(
          deviceLabel: sessions[id]?.label ?? 'unknown',
          record: record,
        ),
      );
    }
    return const _Message({});
  }
}

final class _Message implements IRpcSerializable {
  const _Message(this.fields);
  final Map<String, dynamic> fields;
  @override
  Map<String, dynamic> toJson() => fields;
}
