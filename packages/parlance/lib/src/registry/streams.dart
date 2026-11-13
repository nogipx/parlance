import 'dart:async';
import 'dart:collection';

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

/// The library's bounded, lazy, single-subscription bridge. With [pauseSource],
/// single-subscription sources receive backpressure and must bound their own
/// buffering. Broadcast sources keep running into this bounded queue.
/// The first failure discards pending data and is terminal.
Stream<T> boundedStream<T>(
  Stream<T> Function() source, {
  StreamLimits limits = const StreamLimits(),
  bool pauseSource = false,
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
).stream;

// The stream/controller can outlive its subscription in client code. Keep
// callbacks in explicit nullable fields so closing can release their captures,
// independently of the VM's sharing of closure contexts.
final class _DataBridge<T> {
  _DataBridge(
    this._source,
    this._limits,
    this._weigh,
    this._cancel,
    this._cancelFailure,
    this._onClosed,
    this._pauseSource,
  ) {
    _out = StreamController<T>(
      sync: true,
      onListen: () => scheduleMicrotask(_start),
      onPause: () {
        _paused = true;
        _flow();
      },
      onResume: () {
        _paused = false;
        _drain();
        _flow();
      },
      onCancel: () => _finish(notify: false),
    );
  }

  Stream<T> Function()? _source;
  final StreamLimits _limits;
  int Function(T value)? _weigh;
  CancellationToken? _cancel;
  StreamFailure Function()? _cancelFailure;
  void Function(int items, int bytes, Object? error)? _onClosed;
  late final StreamController<T> _out;
  StreamSubscription<T>? _input;
  IHandle? _cancellation;
  final _pending = Queue<(T, int)>();
  var _held = 0;
  var _items = 0;
  var _bytes = 0;
  final bool _pauseSource;
  var _pausable = false;
  var _inputPaused = false;
  var _paused = false;
  var _stopped = false;
  var _ended = false;

  Stream<T> get stream => _out.stream;

  static void _cancelInput(StreamSubscription<Object?> input) {
    // An owner's cancel can throw or wait on unrelated work. Observe it without
    // retaining this bridge or delaying the consumer's cancellation.
    try {
      unawaited(input.cancel().catchError((Object _, StackTrace _) {}));
    } on Object {
      /* Cleanup cannot prevent releasing the bridge's state. */
    }
  }

  void _finish({Object? error, StackTrace? stack, bool notify = true}) {
    if (_stopped) return;
    _stopped = true;
    final input = _input;
    final onClosed = _onClosed;
    _input = null;
    _source = null;
    _weigh = null;
    _cancel = null;
    _cancelFailure = null;
    _onClosed = null;
    _cancellation?.dispose();
    _cancellation = null;
    _pending.clear();
    _held = 0;
    if (input != null) _cancelInput(input);
    onClosed?.call(_items, _bytes, error);
    if (notify) {
      // A token can be cancelled inside onData: avoid re-entrant delivery.
      scheduleMicrotask(() {
        if (error != null) _out.addError(error, stack);
        unawaited(_out.close());
      });
    }
  }

  void _flow() {
    if (_stopped || !_pausable || _input == null) return;
    // Keep one read ahead: an idle source can still deliver done while paused.
    final stop = _paused && _pending.isNotEmpty;
    if (stop == _inputPaused) return;
    _inputPaused = stop;
    if (stop) {
      _input!.pause();
    } else {
      _input!.resume();
    }
  }

  void _drain() {
    while (!_stopped && !_paused && _pending.isNotEmpty) {
      final (value, weight) = _pending.removeFirst();
      _held -= weight;
      _out.add(value);
    }
    if (!_stopped && _ended && _pending.isEmpty) _finish();
  }

  void _receive(T value) {
    if (_stopped) return;
    try {
      final weight = _weigh!(value);
      // A serializer/weigher is user code and may cancel the subscription.
      if (_stopped) return;
      if ((_limits.elementBytes != null && weight > _limits.elementBytes!) ||
          (_limits.bufferItems != null &&
              _pending.length >= _limits.bufferItems!) ||
          (_limits.bufferBytes != null &&
              _held + weight > _limits.bufferBytes!)) {
        throw const StreamFailure(
          StreamFailureCode.resourceExhausted,
          'the stream element or pending queue exceeded its limit',
        );
      }
      _items++;
      _bytes += weight;
      _pending.add((value, weight));
      _held += weight;
      _drain();
      _flow();
    } on Object catch (e, s) {
      _finish(
        error: e is StreamFailure
            ? e
            : StreamFailure(StreamFailureCode.invalidArgument, '$e'),
        stack: s,
      );
    }
  }

  void _failed(Object e, StackTrace s) => _finish(
    error: e is StreamFailure
        ? e
        : StreamFailure(StreamFailureCode.failed, '$e'),
    stack: s,
  );

  void _start() {
    if (_stopped) return;
    final cancel = _cancel;
    _cancel = null;
    _cancellation = cancel?.onCancel(
      () => _finish(
        error:
            _cancelFailure?.call() ??
            const StreamFailure(
              StreamFailureCode.cancelled,
              'the subscription was cancelled',
            ),
      ),
    );
    if (_stopped) {
      _cancellation?.dispose();
      _cancellation = null;
      return;
    }
    final source = _source!;
    _source = null;
    try {
      final incoming = source();
      _pausable = _pauseSource && !incoming.isBroadcast;
      if (_stopped) return;
      final input = incoming.listen(
        _receive,
        onError: _failed,
        onDone: () {
          _ended = true;
          _drain();
        },
      );
      if (_stopped) {
        // Synchronous sources can finish before listen returns its handle.
        _cancelInput(input);
      } else {
        _input = input;
        _flow();
      }
    } on Object catch (e, s) {
      _failed(e, s);
    }
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
