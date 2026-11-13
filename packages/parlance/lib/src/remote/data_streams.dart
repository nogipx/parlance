import 'dart:async';
import 'package:rpc_dart/rpc_dart.dart';
import '../registry/streams.dart';
import 'contract.dart';

/// Data frames carry terminal failures explicitly, without transport redaction.
Stream<WireJson> encodeDataStream(Stream<Object?> Function() source) =>
    _DataEncoder(source).stream;

final class _DataEncoder {
  _DataEncoder(this._source) {
    _out = StreamController<WireJson>(
      sync: true,
      onListen: () => scheduleMicrotask(_start),
      onPause: () => _input?.pause(),
      onResume: () => _input?.resume(),
      onCancel: _stop,
    );
  }
  Stream<Object?> Function()? _source;
  StreamSubscription<Object?>? _input;
  late final StreamController<WireJson> _out;
  var _stopped = false;
  Stream<WireJson> get stream => _out.stream;

  static void _cancelInput(StreamSubscription<Object?> input) {
    try {
      unawaited(input.cancel().catchError((Object _, StackTrace _) {}));
    } on Object {
      /* Release our own state even if source cleanup throws. */
    }
  }

  void _stop() {
    if (_stopped) return;
    _stopped = true;
    final input = _input;
    _input = null;
    _source = null;
    if (input != null) _cancelInput(input);
  }

  void _failed(Object e, StackTrace s) {
    if (_stopped) return;
    final failure = e is StreamFailure
        ? e
        : StreamFailure(StreamFailureCode.failed, '$e');
    _stop();
    scheduleMicrotask(() {
      _out.add(
        WireJson({'failure': failure.code.name, 'message': failure.message}),
      );
      unawaited(_out.close());
    });
  }

  void _start() {
    if (_stopped) return;
    final source = _source!;
    _source = null;
    try {
      final incoming = source();
      if (_stopped) return;
      final input = incoming.listen(
        (v) {
          if (!_stopped) _out.add(WireJson({'value': v}));
        },
        onError: _failed,
        onDone: () {
          if (_stopped) return;
          _stop();
          unawaited(_out.close());
        },
      );
      if (_stopped) {
        _cancelInput(input);
      } else {
        _input = input;
        if (_out.isPaused) input.pause();
      }
    } on Object catch (e, s) {
      _failed(e, s);
    }
  }
}

/// A remote data stream, including terminal failures and connection loss.
Stream<Object?> decodeDataStream(Stream<WireJson> source) => source.transform(
  StreamTransformer.fromHandlers(
    handleData: (frame, sink) {
      final m = frame.json;
      if (m case {
        'failure': final String code,
        'message': final String message,
      }) {
        sink.addError(
          StreamFailure(
            StreamFailureCode.values.asNameMap()[code] ??
                StreamFailureCode.failed,
            message,
          ),
        );
      } else if (m.containsKey('value')) {
        sink.add(m['value']);
      } else {
        sink.addError(
          const StreamFailure(
            StreamFailureCode.invalidArgument,
            'a malformed stream frame',
          ),
        );
      }
    },
    handleError: (Object e, StackTrace s, sink) {
      sink.addError(
        e is StreamFailure
            ? e
            : StreamFailure(StreamFailureCode.connectionLost, '$e'),
        s,
      );
    },
  ),
);

/// One opening header followed by typed data frames on the same RPC stream.
Stream<WireJson> exchangeRequests(
  Map<String, Object?> header,
  Stream<Object?> input,
) async* {
  yield WireJson({'open': header});
  yield* encodeDataStream(() => input);
}

/// Separates the opening from the input without draining a paused consumer.
/// Cancellation also works while waiting for the first frame or for input.
Stream<Object?> receiveExchange(
  Stream<WireJson> requests,
  Stream<Object?> Function(Map<String, Object?>, Stream<Object?>) serve, {
  RpcContext? context,
}) => _ExchangeReceiver(requests, serve, context).stream;

final class _ExchangeReceiver {
  _ExchangeReceiver(this._requests, this._serve, RpcContext? context) {
    final binding = _cancelBinding;
    binding.cancel = () => _fail(
      const StreamFailure(
        StreamFailureCode.cancelled,
        'the RPC operation was cancelled',
      ),
      StackTrace.current,
    );
    context?.cancellationToken?.cancelled.then((_) => binding.cancel?.call());
    _input = StreamController<WireJson>(
      sync: true,
      onListen: () {
        _waitingInput = false;
        _request?.resume();
      },
      onCancel: () {
        _waitingInput = true;
        _request?.pause();
      },
      onPause: () => _request?.pause(),
      onResume: () => _request?.resume(),
    );
    _out = StreamController<Object?>(
      sync: true,
      onListen: () => scheduleMicrotask(_start),
      onPause: () => _response?.pause(),
      onResume: () => _response?.resume(),
      onCancel: _stop,
    );
  }
  Stream<WireJson>? _requests;
  Stream<Object?> Function(Map<String, Object?>, Stream<Object?>)? _serve;
  StreamSubscription<WireJson>? _request;
  StreamSubscription<Object?>? _response;
  late final StreamController<WireJson> _input;
  late final StreamController<Object?> _out;
  final _cancelBinding = _ExchangeCancellation();
  var _opened = false;
  var _stopped = false;
  var _waitingInput = false;
  Stream<Object?> get stream => _out.stream;

  void _stop() {
    if (_stopped) return;
    _stopped = true;
    _requests = null;
    _serve = null;
    _cancelBinding.cancel = null;
    final request = _request;
    final response = _response;
    _request = null;
    _response = null;
    if (request != null) _DataEncoder._cancelInput(request);
    if (response != null) _DataEncoder._cancelInput(response);
    unawaited(_input.close());
  }

  void _fail(Object e, StackTrace s) {
    if (_stopped) return;
    _stop();
    scheduleMicrotask(() {
      _out.addError(e, s);
      unawaited(_out.close());
    });
  }

  void _frame(WireJson frame) {
    if (_stopped) return;
    if (_opened) {
      _input.add(frame);
      return;
    }
    try {
      final header = frame.json['open'];
      if (header is! Map) {
        throw const StreamFailure(
          StreamFailureCode.invalidArgument,
          'an input stream needs an opening header',
        );
      }
      _opened = true;
      _waitingInput = true;
      _request?.pause();
      final serve = _serve!;
      _serve = null;
      final response = serve(
        header.cast<String, Object?>(),
        decodeDataStream(_input.stream),
      );
      if (_stopped) return;
      final subscription = response.listen(
        (v) {
          if (!_stopped) _out.add(v);
        },
        onError: _fail,
        onDone: () {
          if (!_stopped) {
            _stop();
            unawaited(_out.close());
          }
        },
      );
      if (_stopped) {
        _DataEncoder._cancelInput(subscription);
      } else {
        _response = subscription;
        if (_out.isPaused) subscription.pause();
      }
    } on Object catch (e, s) {
      _fail(e, s);
    }
  }

  void _start() {
    if (_stopped) return;
    final requests = _requests!;
    _requests = null;
    try {
      final subscription = requests.listen(
        _frame,
        onError: _fail,
        onDone: () {
          if (!_opened) {
            _fail(
              const StreamFailure(
                StreamFailureCode.invalidArgument,
                'the input ended without an opening header',
              ),
              StackTrace.current,
            );
          } else if (!_input.isClosed) {
            unawaited(_input.close());
          }
        },
      );
      if (_stopped) {
        _DataEncoder._cancelInput(subscription);
      } else {
        _request = subscription;
        if (_waitingInput) subscription.pause();
      }
    } on Object catch (e, s) {
      _fail(e, s);
    }
  }
}

final class _ExchangeCancellation {
  void Function()? cancel;
}

/// Negotiated limits are protocol data, not part of the public configuration API.
Map<String, Object?> streamLimitsToJson(StreamLimits limits) => {
  'subscriptions': limits.subscriptions,
  'bufferItems': limits.bufferItems,
  'bufferBytes': limits.bufferBytes,
  'elementBytes': limits.elementBytes,
};

/// Reads peer limits; omitted fields use ordinary defaults.
StreamLimits streamLimitsFromJson(Object? json) {
  final m = json is Map ? json : const <String, Object?>{};
  int? read(String key, int fallback) {
    if (!m.containsKey(key)) return fallback;
    final v = m[key];
    if (v == null || (v is int && v > 0)) return v as int?;
    throw FormatException('invalid stream limit $key');
  }

  return StreamLimits(
    subscriptions: read('subscriptions', 16),
    bufferItems: read('bufferItems', 64),
    bufferBytes: read('bufferBytes', 1 << 20),
    elementBytes: read('elementBytes', 256 << 10),
  );
}
