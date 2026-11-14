import 'dart:async';
import 'package:rpc_dart/internal.dart'
    show BoundedStreamBridge, StreamBufferLimits, StreamBridgeStats;

import '../core/core.dart';
import 'cancellation.dart';

/// Why a stream subscription ended unsuccessfully.
enum StreamFailureCode {
  /// The word does not exist.
  missing,

  /// The subscriber may not open it.
  notPermitted,

  /// The parameters or an element do not match the word.
  invalidArgument,

  /// The owner cannot provide the stream now, or was withdrawn.
  unavailable,

  /// The owner failed.
  failed,

  /// The caller's cancellation token was cancelled.
  cancelled,

  /// A subscription, element or pending queue exceeded a limit.
  resourceExhausted,

  /// A connection carrying the subscription was lost.
  connectionLost,

  /// The peer does not support stream words.
  unsupported,
}

/// A terminal stream failure, with a stable [code] across connections.
final class StreamFailure implements Exception {
  /// A failure explained by [message].
  const StreamFailure(this.code, this.message);

  /// Its programmatic reason.
  final StreamFailureCode code;

  /// What happened.
  final String message;

  @override
  String toString() => 'StreamFailure(${code.name}): $message';
}

/// Bounds on active subscriptions and on each Parlance data queue.
/// Owner and transport buffers are outside these bounds.
final class StreamLimits {
  /// Defaults for ordinary data streams; null disables an individual bound.
  const StreamLimits({
    this.subscriptions = 16,
    this.bufferItems = 64,
    this.bufferBytes = 1 << 20,
    this.elementBytes = 256 << 10,
  }) : assert(subscriptions == null || subscriptions > 0),
       assert(bufferItems == null || bufferItems > 0),
       assert(bufferBytes == null || bufferBytes > 0),
       assert(elementBytes == null || elementBytes > 0);

  /// No bounds, for trusted sources and consumers.
  static const unbounded = StreamLimits(
    subscriptions: null,
    bufferItems: null,
    bufferBytes: null,
    elementBytes: null,
  );

  /// Active subscriptions consumed by one participant. Remote participants
  /// also apply this bound separately to subscriptions they provide.
  final int? subscriptions;

  /// Pending elements of one subscription.
  final int? bufferItems;

  /// Approximate JSON bytes pending in one subscription.
  final int? bufferBytes;

  /// Approximate JSON bytes of one element.
  final int? elementBytes;
}

/// Internal policy merging, excluded from the public StreamLimits surface.
extension StreamLimitPolicy on StreamLimits {
  /// Tightens these bounds with [other]; neither side can relax the other.
  StreamLimits restrict(StreamLimits other) {
    int? smaller(int? a, int? b) => a == null
        ? b
        : b == null
        ? a
        : (a < b ? a : b);
    return StreamLimits(
      subscriptions: smaller(subscriptions, other.subscriptions),
      bufferItems: smaller(bufferItems, other.bufferItems),
      bufferBytes: smaller(bufferBytes, other.bufferBytes),
      elementBytes: smaller(elementBytes, other.elementBytes),
    );
  }
}

/// Internal payload-free counters supplied by the shared bridge.
typedef DataStreamStats = StreamBridgeStats;

/// The library's bounded, lazy, single-subscription bridge. With [pauseSource],
/// single-subscription sources receive backpressure and must bound their own
/// buffering. Broadcast sources keep running into this bounded queue.
/// The first failure discards pending data and is terminal.
Stream<T> boundedStream<T>(
  Stream<T> Function() source, {
  StreamLimits limits = const StreamLimits(),
  bool pauseSource = false,
  bool deferStart = true,
  DataStreamStats? stats,
  required int Function(T value) weigh,
  CancellationToken? cancel,
  StreamFailure Function()? cancelFailure,
  void Function(int items, int bytes, Object? error)? onClosed,
}) => _DataBridge(
  source,
  limits,
  weigh,
  cancel,
  cancelFailure,
  onClosed,
  pauseSource,
  stats,
  deferStart,
).stream;

// The stream/controller can outlive its subscription in client code. Keep
// callbacks in explicit nullable fields so closing can release their captures,
// independently of the VM's sharing of closure contexts.
final class _DataBridge<T> {
  _DataBridge(
    this._source,
    StreamLimits limits,
    int Function(T) weigh,
    this._cancel,
    this._cancelFailure,
    this._onClosed,
    bool pauseSource,
    DataStreamStats? stats,
    bool deferStart,
  ) {
    _bridge = BoundedStreamBridge<T>(
      source: _make,
      weigh: weigh,
      limits: StreamBufferLimits(
        items: limits.bufferItems,
        bytes: limits.bufferBytes,
        elementBytes: limits.elementBytes,
      ),
      stats: stats,
      pauseSource: pauseSource,
      deferStart: deferStart,
      onStart: _start,
      overflowError: () => const StreamFailure(
        StreamFailureCode.resourceExhausted,
        'the stream element or pending queue exceeded its limit',
      ),
      sourceError: (error, _) => error is StreamFailure
          ? error
          : StreamFailure(StreamFailureCode.failed, '$error'),
      elementError: (error, _) => error is StreamFailure
          ? error
          : StreamFailure(StreamFailureCode.invalidArgument, '$error'),
      onClosed: _closed,
    );
  }
  late final BoundedStreamBridge<T> _bridge;
  Stream<T> Function()? _source;
  CancellationToken? _cancel;
  StreamFailure Function()? _cancelFailure;
  void Function(int, int, Object?)? _onClosed;
  IHandle? _cancellation;

  Stream<T> get stream => _bridge.stream;

  Stream<T> _make() {
    final make = _source!;
    _source = null;
    return make();
  }

  void _start() {
    final cancel = _cancel;
    _cancel = null;
    _cancellation = cancel?.onCancel(
      () => _bridge.fail(
        _cancelFailure?.call() ??
            const StreamFailure(
              StreamFailureCode.cancelled,
              'the subscription was cancelled',
            ),
      ),
    );
    if (_bridge.isClosed) {
      _cancellation?.dispose();
      _cancellation = null;
    }
  }

  void _closed(int items, int bytes, Object? error) {
    final closed = _onClosed;
    _source = null;
    _cancel = null;
    _cancelFailure = null;
    _onClosed = null;
    _cancellation?.dispose();
    _cancellation = null;
    closed?.call(items, bytes, error);
  }
}

/// The library's lifetime of one subscription, including its terminal reason.
final class StreamLease {
  /// An active subscription.
  StreamLease();

  /// Signals termination to the bounded bridge.
  final token = CancellationToken();

  /// The reason delivered on termination.
  StreamFailure failure = const StreamFailure(
    StreamFailureCode.cancelled,
    'the subscription was cancelled',
  );

  /// Ends it once, retaining the first terminal reason.
  void end(StreamFailure why) {
    if (token.isCancelled) return;
    failure = why;
    token.cancel();
  }
}

/// The library's lazy stream: resolves the participant only on its one listen.
final class LazyDataStream<T> extends Stream<T> {
  /// [make] is invoked only on the first listen.
  LazyDataStream(Stream<T> Function() make) : _make = make;

  Stream<T> Function()? _make;
  @override
  StreamSubscription<T> listen(
    void Function(T)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final make = _make;
    if (make == null) {
      throw StateError('the stream has already been listened to');
    }
    _make = null;
    Stream<T> stream;
    try {
      stream = make();
    } on Object catch (e, s) {
      stream = Stream<T>.error(e, s);
    }
    return stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}
