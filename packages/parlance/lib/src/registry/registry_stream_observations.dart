part of 'registry.dart';

/// A streaming operation's lifecycle event, available to host tools.
enum StreamEventKind {
  /// Admission succeeded; the owner is about to be invoked.
  opened,

  /// An admitted operation ended.
  closed,

  /// Admission failed before the owner ran.
  rejected,
}

/// The final disposition, independent of how the consumer stopped listening.
enum StreamTermination {
  /// The output completed normally.
  completed,

  /// The consumer or its cancellation token ended the operation.
  cancelled,

  /// The operation ended with a terminal failure.
  failed,

  /// The owner was never invoked.
  rejected,
}

/// Immutable counters for one direction. Bytes are estimates, not wire traffic.
final class StreamTraffic {
  StreamTraffic._(DataStreamStats stats)
    : items = stats.items,
      bytes = stats.bytes,
      delivered = stats.delivered,
      pendingItems = stats.pendingItems,
      pendingBytes = stats.pendingBytes,
      peakItems = stats.peakItems,
      peakBytes = stats.peakBytes,
      paused = stats.paused,
      closed = stats.closed,
      sourceDone = stats.sourceDone;

  /// Elements admitted after validation, including queued elements.
  final int items;

  /// Estimated size of admitted elements.
  final int bytes;

  /// Elements handed to this direction's consumer.
  final int delivered;

  /// Elements currently queued in Parlance.
  final int pendingItems;

  /// Estimated bytes currently queued in Parlance.
  final int pendingBytes;

  /// Largest observed queue, in elements.
  final int peakItems;

  /// Largest observed queue, in estimated bytes.
  final int peakBytes;

  /// Whether its consumer has paused delivery.
  final bool paused;

  /// Whether the subscription has been released.
  final bool closed;

  /// Whether the source has finished sending, including an input half-close.
  final bool sourceDone;
}

/// A read-only, payload-free snapshot; safe to retain after the operation ends.
final class StreamSnapshot {
  StreamSnapshot._(_StreamObservation observation, DateTime now)
    : id = observation.id,
      word = observation.word,
      kind = observation.kind,
      by = observation.cause.by,
      cause = observation.cause,
      startedAt = observation.startedAt,
      elapsed = now.isBefore(observation.startedAt)
          ? Duration.zero
          : now.difference(observation.startedAt),
      input = StreamTraffic._(observation.input),
      output = StreamTraffic._(observation.output),
      termination = observation.termination,
      failure = observation.failure,
      failureMessage = observation.failureMessage,
      traceparent = observation.span.traceparent;

  /// One opening, never reused for a retry.
  final String id;

  /// The word as requested, preserving alias usage.
  final String word;

  /// Its atomic interaction kind.
  final String kind;

  /// Who opened the operation.
  final Principal by;

  /// The verified cause of the opening.
  final Cause cause;

  /// When opening began.
  final DateTime startedAt;

  /// Time since opening, fixed at the end for a final event.
  final Duration elapsed;

  /// Counters of incoming data (empty for a server stream).
  final StreamTraffic input;

  /// Counters of outgoing data or the final client-stream result.
  final StreamTraffic output;

  /// Null while active.
  final StreamTermination? termination;

  /// Stable terminal failure, if any; no payload or exception capture.
  final StreamFailureCode? failure;

  /// Bounded, payload-free detail of the terminal failure.
  final String? failureMessage;

  /// W3C trace context when tracing is enabled.
  final String? traceparent;
}

/// A lifecycle event, without per-element data or retained history.
final class StreamEvent {
  StreamEvent._(this.kind, this.stream);

  /// Whether it opened, ended or was refused before invocation.
  final StreamEventKind kind;

  /// The operation at that point in time.
  final StreamSnapshot stream;
}

final class _StreamObservation {
  _StreamObservation(
    this.registry,
    this.id,
    this.word,
    this.kind,
    this.cause, {
    required this.input,
    required this.output,
  }) : startedAt = registry.clock.now();
  final Registry registry;
  final String id;
  final String word;
  final String kind;
  final Cause cause;
  final DateTime startedAt;
  final DataStreamStats input;
  final DataStreamStats output;
  LogSpanHandle span = noSpan;
  StreamTermination? termination;
  StreamFailureCode? failure;
  String? failureMessage;
  bool admitted = false;

  StreamSnapshot snapshot() => StreamSnapshot._(this, registry.clock.now());

  void open() {
    admitted = true;
    span = registry._trace.open(
      id,
      word,
      Kept.json(const {}),
      cause,
      query: false,
      streamKind: kind,
    );
    registry._activeStreams[id] = this;
    if (registry.log.isEnabled(RpcLogLevel.info)) {
      registry.log.info(
        'stream opened',
        data: {
          'subscription': id,
          'word': word,
          'kind': kind,
          'by': cause.by.selector,
        },
      );
    }
    registry._emitStreamEvent(
      StreamEvent._(StreamEventKind.opened, snapshot()),
    );
  }

  void close(Object? error) {
    if (termination != null) return;
    input.closed = true;
    input.paused = false;
    input.pendingItems = 0;
    input.pendingBytes = 0;
    failure = error is StreamFailure
        ? error.code
        : error == null
        ? null
        : StreamFailureCode.failed;
    final detail = error is StreamFailure ? error.message : error?.toString();
    failureMessage = detail == null
        ? null
        : detail.length > 1024
        ? detail.substring(0, 1024)
        : detail;
    termination = !admitted
        ? StreamTermination.rejected
        : output.cancelled || failure == StreamFailureCode.cancelled
        ? StreamTermination.cancelled
        : error == null
        ? StreamTermination.completed
        : StreamTermination.failed;
    registry._activeStreams.remove(id);
    final data = <String, Object>{
      'subscription': id,
      'word': word,
      'kind': kind,
      'by': cause.by.selector,
      'termination': termination!.name,
      'failure': ?failure?.name,
      'inputItems': input.items,
      'inputBytes': input.bytes,
      'outputItems': output.items,
      'outputBytes': output.bytes,
      'items': output.items,
      'bytes': output.bytes,
      'elapsedMicros': registry.clock
          .now()
          .difference(startedAt)
          .inMicroseconds,
    };
    if (registry.log.isEnabled(RpcLogLevel.info)) {
      registry.log.info(
        admitted ? 'stream closed' : 'stream rejected',
        data: data,
      );
    }
    span.addData(data);
    registry._trace.close(
      id,
      span,
      error != null && failure != StreamFailureCode.cancelled
          ? CallFailed(error, StackTrace.empty)
          : const CallDone(null),
    );
    registry._emitStreamEvent(
      StreamEvent._(
        admitted ? StreamEventKind.closed : StreamEventKind.rejected,
        snapshot(),
      ),
    );
  }
}
