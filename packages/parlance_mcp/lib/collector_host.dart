/// An outbound connection from a Parlance host to a diagnostic collector.
library;

import 'dart:async';

import 'package:parlance/app.dart';
import 'package:parlance/tools.dart' show HostRegistry;
import 'package:rpc_dart/rpc_dart.dart';
import 'package:rpc_dart_log/rpc_dart_log.dart';
import 'package:rpc_dart_websocket/rpc_dart_websocket.dart';
import 'src/collector_protocol.dart';
import 'src/journal_feed.dart';

/// Keeps a diagnostic session connected until [close]. The host applies the
/// access declarations for the diagnostic principal to each new session.
final class CollectorHost {
  /// Connects the host and streams [logs] to the same collector [address].
  /// Set [commandTools] to expose commands permitted for [principal] to the agent.
  /// Set [shareJournal] to share the host-wide, payload-free execution journal.
  CollectorHost({
    required Host host,
    required Principal principal,
    required Uri address,
    required String app,
    required String device,
    required LogController logs,
    bool commandTools = false,
    bool shareJournal = false,
  }) : _logs = logs {
    if (!{'ws', 'wss'}.contains(address.scheme) ||
        address.host.isEmpty ||
        app.trim().isEmpty ||
        device.trim().isEmpty) {
      throw ArgumentError(
        'Expected a WebSocket URL and nonempty app and device labels',
      );
    }
    _output = LogCollectorOutput(
      uri: address,
      device: DeviceInfo(name: device, app: app),
    );
    _logs.addOutput(_output);
    final journal = shareJournal ? JournalFeed(host.registry.journal) : null;
    final uri = address.replace(
      queryParameters: {
        ...address.queryParameters,
        'journal': (journal != null).toString(),
        'commandTools': commandTools.toString(),
        'app': app,
        'device': '$device/${_output.sessionId}',
      },
    );
    _done = _connect(host, principal, uri, journal).whenComplete(() async {
      _logs.removeOutput(_output);
      _output.dispose();
      await journal?.close();
    });
  }

  final LogController _logs;
  late final LogCollectorOutput _output;
  final _cancel = RpcCancellationToken();
  late final Future<void> _done;
  IRemoteSession? _session;
  Timer? _retry;
  Completer<void>? _waiting;

  Future<void> _connect(
    Host host,
    Principal principal,
    Uri uri,
    JournalFeed? journal,
  ) async {
    var seconds = 1;
    while (!_cancel.isCancelled) {
      RpcPeerEndpoint? peer;
      try {
        final transport = await RpcWebSocketCallerTransport.connect(
          uri,
          protocols: const [collectorHostProtocol],
          cancellationToken: _cancel,
        );
        peer = RpcPeerEndpoint(transport: transport);
        if (_cancel.isCancelled) break;
        if (journal != null) {
          peer.registerServiceContract(JournalPeer(peer, journal));
        }
        final session = _session = host.serve(principal, peer);
        peer.start();
        seconds = 1;
        await session.ended;
      } on Object catch (error) {
        if (error is StateError || error is ArgumentError) rethrow;
        // The next attempt also covers a collector that has not started yet.
      } finally {
        _session?.dispose();
        _session = null;
        await peer?.close();
      }
      if (_cancel.isCancelled) break;
      final waiting = _waiting = Completer<void>();
      _retry = Timer(Duration(seconds: seconds), waiting.complete);
      await waiting.future;
      _waiting = null;
      seconds = (seconds * 2).clamp(1, 30);
    }
  }

  /// Completes on shutdown, or with an error if the host rejects the principal.
  Future<void> get done => _done;

  /// Stops retries, withdraws the session and releases the connection.
  Future<void> close() {
    _cancel.cancel();
    _session?.dispose();
    _retry?.cancel();
    final waiting = _waiting;
    if (waiting != null && !waiting.isCompleted) waiting.complete();
    return _done;
  }
}
