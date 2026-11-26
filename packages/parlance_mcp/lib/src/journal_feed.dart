import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:parlance/tools.dart' show JournalEntry;
import 'package:rpc_dart/rpc_dart.dart';

/// One bounded, metadata-only recording per opted-in connector. The host's
/// journal position is preserved inside each entry; cursors address the feed.
final class JournalFeed {
  JournalFeed(Stream<JournalEntry> source) {
    _subscription = source.listen(
      _record,
      onError: (Object error) {
        _failure = error.toString();
      },
      onDone: () => _ended = true,
    );
  }

  late final StreamSubscription<JournalEntry> _subscription;
  final _rows = Queue<({int cursor, String json, int bytes})>();
  int _position = 0, _bytes = 0;
  bool _ended = false;
  String? _failure;

  void _record(JournalEntry event) {
    final cursor = ++_position;
    final json = jsonEncode(event.toJson(payloads: false));
    if (json.length > 65536) return;
    final bytes = utf8.encode(json).length;
    if (bytes > 65536) return;
    _rows.add((cursor: cursor, json: json, bytes: bytes));
    _bytes += bytes;
    while (_rows.length > 1024 || _bytes > 1024 * 1024) {
      _bytes -= _rows.removeFirst().bytes;
    }
  }

  Map<String, dynamic> page(int after) {
    final lines = <String>[];
    var cursor = after, dropped = 0, size = 0, more = false;
    for (final row in _rows) {
      if (row.cursor <= after) continue;
      if (lines.length >= 128 || size + row.bytes > 128 * 1024) {
        more = true;
        break;
      }
      dropped += row.cursor - cursor - 1;
      cursor = row.cursor;
      lines.add(row.json);
      size += row.bytes;
    }
    if (!more && _position > cursor) {
      dropped += _position - cursor;
      cursor = _position;
    }
    return {
      'lines': lines,
      'cursor': cursor,
      'dropped': dropped,
      'more': more,
      'ended': _ended,
      if (_failure != null) 'error': _failure,
    };
  }

  Future<void> close() => _subscription.cancel();
}

final class _Page implements IRpcSerializable {
  const _Page(this.json);
  final Map<String, dynamic> json;
  @override
  Map<String, dynamic> toJson() => json;
}

final class JournalPeer extends RpcPeerContract {
  JournalPeer(RpcPeerEndpoint endpoint, [this.feed])
    : super('CollectorJournal', endpoint);
  final JournalFeed? feed;
  static const _codec = RpcCodec<_Page>(_Page.new);
  @override
  void setup() {
    final source = feed;
    if (source == null) return;
    addUnaryMethod<_Page, _Page>(
      methodName: 'page',
      requestCodec: _codec,
      responseCodec: _codec,
      handler: (request, {RpcContext? context}) async =>
          _Page(source.page(request.json['after'] as int)),
    );
  }

  Future<Map<String, dynamic>> read(int after) async {
    final reply = await callUnary<_Page, _Page>(
      methodName: 'page',
      requestCodec: _codec,
      responseCodec: _codec,
      request: _Page({'after': after}),
    );
    return reply.json;
  }
}
