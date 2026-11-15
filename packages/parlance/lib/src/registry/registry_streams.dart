part of 'registry.dart';

/// Provides the source for one data subscription.
typedef StreamHandler = Stream<Object?> Function(StreamCall call);

/// A stream opening, including its caller and immutable parameters.
final class StreamCall {
  /// The library's opening context, also used by remote owners.
  StreamCall(
    this.id,
    this.word,
    Kept params,
    this.cause,
    this.expired, {
    this.itemShape,
    this.traceparent,
    this.input,
    this.inputShape,
    this.kind = 'serverStream',
  }) : _params = params;

  /// The identity of this subscription, never reused for retries.
  final String id;

  /// Its stream word.
  final String word;
  final Kept _params;

  /// Its parameters as JSON.
  Map<String, Object?> get params => _params.json! as Map<String, Object?>;

  /// Parameters kept as typed values locally, decoded at a connection edge.
  T paramsAs<T>(Shape<T> shape) => _params.asShape(shape);

  /// Who opened it and what the opening follows from.
  final Cause cause;

  /// Who opened it.
  Principal get by => cause.by;

  /// Cancelled when this subscription ends.
  final CancellationToken expired;

  /// Its atomic word kind.
  final String kind;

  /// Admitted input sequence; completion only closes the input direction.
  final Stream<Object?>? input;

  /// Representation of input elements; null means JSON.
  final Shape<Object?>? inputShape;

  /// Reads each input in the owner's declared representation.
  Stream<T> inputAs<T>(Shape<T> shape) => input!.map(
    (v) => identical(inputShape, shape) ? v as T : shape.fromJson(v),
  );

  /// Trace context of the semantic operation, never of individual elements.
  final String? traceparent;

  /// The representation its handler returns; null means JSON.
  final Shape<Object?>? itemShape;
}

final class _StreamEntry {
  _StreamEntry(
    this.descriptor,
    this.handler,
    this.whyNot,
    this.params,
    this.item,
    this.input,
  );
  final DataStreamDescriptor descriptor;
  final StreamHandler handler;
  final WhyNot? whyNot;
  final Shape<Object?> params;
  final Shape<Object?> item;
  final Shape<Object?>? input;
  final Set<StreamLease> open = {};
}

/// The library's definitions and subscriptions for data streams.
extension RegistryStreams on Registry {
  /// Ends subscriptions before removing remote words, preserving the reason
  /// that their owner disappeared (connection loss versus withdrawal).
  void endTargetStreams(Iterable<String> names, StreamFailure failure) {
    for (final name in names) {
      for (final lease in [...?_streams[name]?.open]) {
        lease.end(failure);
      }
    }
  }

  /// Defines a data stream. Removing it terminates all active subscriptions.
  IHandle defineStream(
    DataStreamDescriptor d,
    StreamHandler handler, {
    WhyNot? whyNot,
    Shape<Object?>? params,
    Shape<Object?>? item,
    Shape<Object?>? input,
  }) {
    _checkFree(d.name);
    _checkKnown(d);
    _checkAccess(d);
    _streams[d.name] = _StreamEntry(
      d,
      handler,
      whyNot,
      params != null && params.keptAsIs ? params : JsonValue(d.params),
      item != null && item.keptAsIs ? item : JsonValue(d.type),
      d.input == null
          ? null
          : (input != null && input.keptAsIs ? input : JsonValue(d.input!)),
    );
    _announce(DescriptorAdded(d));
    return Disposer(() => _undefine(d.name));
  }

  /// Opens one lazy stream. Elements are neither retained nor committed.
  Stream<T> openStream<T>(
    String name,
    Kept params,
    Shape<T> itemShape, {
    required Principal by,
    Stream<Object?>? input,
    Shape<Object?>? inputShape,
    String kind = 'serverStream',
    Cause? cause,
    CancellationToken? cancel,
    StreamLimits? limits,
    StreamLease? lifetime,
    void Function()? onClosed,
  }) {
    final bounds = this.limits.streams.restrict(
      limits ?? StreamLimits.unbounded,
    );
    final lease = lifetime ?? StreamLease();
    _StreamEntry? entry;
    IHandle? cancelled;
    IHandle? use;
    _StreamObservation? observation;
    final inputStats = DataStreamStats();
    final outputStats = DataStreamStats();
    var registered = false;
    final id = newId();
    return boundedStream<T>(
      () {
        if (cancel?.isCancelled ?? false) {
          throw const StreamFailure(
            StreamFailureCode.cancelled,
            'the subscription was cancelled',
          );
        }
        refuseInQuery('open stream $name');
        if (_disposing) {
          throw const StreamFailure(
            StreamFailureCode.unavailable,
            'the host ended',
          );
        }
        observation = _StreamObservation(
          this,
          id,
          name,
          kind,
          _inConversation(cause ?? Cause(by)),
          input: inputStats,
          output: outputStats,
        );
        final found = _streams[name];
        if (found == null) throw StreamFailure(StreamFailureCode.missing, name);
        if (found.descriptor.kind != kind ||
            (found.input != null) != (input != null)) {
          throw const StreamFailure(
            StreamFailureCode.invalidArgument,
            'the stream word has a different interaction type',
          );
        }
        if (!mayRead(by, name)) {
          throw StreamFailure(
            StreamFailureCode.notPermitted,
            '$by may not subscribe to $name',
          );
        }
        if (found.whyNot?.call() case final why?) {
          throw StreamFailure(StreamFailureCode.unavailable, why);
        }
        Kept admitted;
        try {
          admitted = _admitParams(found.params, params);
        } on Object catch (e) {
          throw StreamFailure(StreamFailureCode.invalidArgument, '$e');
        }
        // Availability and serializers are user code: they may withdraw an owner.
        if (_disposing || !identical(_streams[name], found)) {
          throw const StreamFailure(
            StreamFailureCode.unavailable,
            'the stream owner was withdrawn during admission',
          );
        }
        if (!mayRead(by, name)) {
          throw StreamFailure(
            StreamFailureCode.notPermitted,
            '$by may not use $name',
          );
        }
        final reader = by.owner.isEmpty ? by : Principal(by.kind, by.id);
        final active = _streamReaders.putIfAbsent(reader, () => {});
        if (bounds.subscriptions case final max? when active.length >= max) {
          if (active.isEmpty) _streamReaders.remove(reader);
          throw const StreamFailure(
            StreamFailureCode.resourceExhausted,
            'too many active stream subscriptions',
          );
        }
        entry = found;
        active.add(lease);
        found.open.add(lease);
        registered = true;
        cancelled = cancel?.onCancel(() => lease.token.cancel());
        if (lease.token.isCancelled) throw lease.failure;
        _streamLeases[id] = lease;
        _warnAccess(
          name,
          by,
          AccessOperation.openStream,
          id: id,
          cause: observation!.cause,
        );
        usedBy(name, by);
        use = _uses.listening(name, by);
        _converse(id, name, observation!.cause);
        observation!.open();
        if (lease.token.isCancelled) throw lease.failure;
        final call = StreamCall(
          id,
          found.descriptor.name,
          admitted,
          observation!.cause,
          lease.token,
          traceparent: observation!.span.traceparent,
          itemShape: found.item,
          kind: kind,
          inputShape: found.input,
          input: input == null
              ? null
              : boundedStream<Object?>(
                  () => input.map((v) {
                    try {
                      final value =
                          inputShape == null ||
                              identical(inputShape, found.input)
                          ? v
                          : found.input!.fromJson(inputShape.toJson(v));
                      return found.input!.check(value);
                    } on Object catch (e) {
                      throw StreamFailure(
                        StreamFailureCode.invalidArgument,
                        '$e',
                      );
                    }
                  }),
                  pauseSource: true,
                  limits: bounds,
                  stats: inputStats,
                  weigh: (v) => jsonWeight(found.input!.toJson(v)),
                  cancel: lease.token,
                  onClosed: (_, _, error) {
                    if (error != null) {
                      lease.end(
                        error is StreamFailure
                            ? error
                            : StreamFailure(StreamFailureCode.failed, '$error'),
                      );
                    }
                  },
                ),
        );
        var count = 0;
        final result = found.handler(call).map((value) {
          try {
            if (kind == 'clientStream' && ++count > 1) {
              throw const StreamFailure(
                StreamFailureCode.invalidArgument,
                'a client stream returns exactly one result',
              );
            }
            final checked = found.item.check(value);
            if (identical(itemShape, found.item)) return checked as T;
            return itemShape.fromJson(found.item.toJson(checked));
          } on Object catch (e) {
            throw StreamFailure(StreamFailureCode.invalidArgument, '$e');
          }
        });
        if (kind != 'clientStream') return result;
        return result.transform(
          StreamTransformer.fromHandlers(
            handleDone: (sink) {
              if (count == 0) {
                sink.addError(
                  const StreamFailure(
                    StreamFailureCode.invalidArgument,
                    'a client stream ended without its result',
                  ),
                );
              }
              sink.close();
            },
          ),
        );
      },
      limits: bounds,
      stats: outputStats,
      pauseSource: true,
      weigh: (x) => jsonWeight(itemShape.toJson(x)),
      cancel: lease.token,
      cancelFailure: () => lease.failure,
      onClosed: (items, bytes, error) {
        cancelled?.dispose();
        if (registered) {
          _streamLeases.remove(id);
          final reader = by.owner.isEmpty ? by : Principal(by.kind, by.id);
          final active = _streamReaders[reader];
          active?.remove(lease);
          if (active?.isEmpty ?? false) _streamReaders.remove(reader);
          entry?.open.remove(lease);
        }
        use?.dispose();
        use = null;
        lease.token.cancel();
        observation?.close(error);
        observation = null;
        onClosed?.call();
      },
    );
  }
}
