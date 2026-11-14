part of 'participant.dart';

final class _DataSource implements _CheckedWord {
  _DataSource(this.d, this.handler, this.whyNot, this.as);
  @override
  final DataStreamDescriptor d;
  final StreamHandler handler;
  @override
  final WhyNot? whyNot;
  @override
  final Principal? as;
  final Set<StreamLease> open = {};
  @override
  String? why;
  @override
  bool told = false;
}

extension on RemoteParticipant {
  bool _supportsData(String kind) =>
      _speaks.contains('streams') &&
      (kind == 'serverStream' || _speaks.contains('inputStreams'));

  void _endData(StreamFailure failure) {
    for (final lease in [..._data.keys]) {
      lease.end(failure);
    }
  }

  void _mayOpenData({
    bool providing = false,
    String kind = 'serverStream',
    bool reserved = false,
  }) {
    if (_disposed || _ended) {
      throw const StreamFailure(
        StreamFailureCode.unavailable,
        'the participant ended',
      );
    }
    if (!_online) {
      throw const StreamFailure(
        StreamFailureCode.connectionLost,
        'the connection is offline',
      );
    }
    if (kind != 'serverStream' &&
        kind != 'clientStream' &&
        kind != 'bidiStream') {
      throw const StreamFailure(
        StreamFailureCode.invalidArgument,
        'unknown streaming interaction type',
      );
    }
    if (!_supportsData(kind)) {
      throw const StreamFailure(
        StreamFailureCode.unsupported,
        'the host does not speak streams',
      );
    }
    if (reserved) return;
    final active = providing
        ? _providedData.length
        : _data.length - _providedData.length;
    if (_dataLimits.subscriptions case final max? when active >= max) {
      throw const StreamFailure(
        StreamFailureCode.resourceExhausted,
        'too many active stream subscriptions',
      );
    }
  }

  IHandle _defineStream(
    DataStreamDescriptor raw,
    StreamHandler handler,
    WhyNot? whyNot,
    Principal? as,
  ) {
    _mayDefine(raw);
    if (!_supportsData(raw.kind)) {
      throw const StreamFailure(
        StreamFailureCode.unsupported,
        'the host does not speak streams',
      );
    }
    final d = access.dataStream(raw);
    final source = _DataSource(d, handler, whyNot, as);
    _streams[d.name] = source;
    _ask({
      'op': 'define',
      'descriptor': d.toJson(),
      ...RemoteParticipant._asOf(as),
    });
    return Disposer(() {
      if (!identical(_streams[d.name], source)) return;
      _streams.remove(d.name);
      for (final lease in [...source.open]) {
        lease.end(
          const StreamFailure(
            StreamFailureCode.unavailable,
            'the stream owner was withdrawn',
          ),
        );
      }
      if (_supportsData(raw.kind)) {
        _ask({'op': 'undefine', 'name': d.name});
      }
    });
  }

  Stream<T> _openData<T>(
    String name,
    Object? params,
    Shape<Object?> paramsShape,
    Shape<T> itemShape, {
    CancellationToken? cancel,
    Stream<Object?>? input,
    Shape<Object?>? inputShape,
    String kind = 'serverStream',
    Principal? as,
  }) {
    final lease = StreamLease();
    IHandle? cancelled;
    final rpcCancel = RpcCancellationToken();
    return boundedStream<T>(
      () {
        if (cancel?.isCancelled ?? false) {
          throw const StreamFailure(
            StreamFailureCode.cancelled,
            'the subscription was cancelled',
          );
        }
        refuseInQuery('open stream $name');
        _mayOpenData(kind: kind);
        if ((kind != 'serverStream') != (input != null)) {
          throw const StreamFailure(
            StreamFailureCode.invalidArgument,
            'input does not match the stream interaction type',
          );
        }
        _data[lease] = as ?? who;
        cancelled = cancel?.onCancel(lease.token.cancel);
        if (lease.token.isCancelled) throw lease.failure;
        Map<String, Object?> parameters;
        try {
          parameters = (paramsShape.toJson(params)! as Map)
              .cast<String, Object?>();
        } on Object catch (e) {
          throw StreamFailure(StreamFailureCode.invalidArgument, '$e');
        }
        final header = {
          'name': name,
          'params': parameters,
          'parent': ?inReplyAs(as ?? who)?.parent,
          ...RemoteParticipant._asOf(as),
        };
        final context = RpcContext.empty().withCancellation(rpcCancel);
        final requests = input == null
            ? null
            : exchangeRequests(
                header,
                boundedStream<Object?>(
                  () => input.map((v) {
                    try {
                      return inputShape == null
                          ? freezeJson(v)
                          : inputShape.toJson(v);
                    } on Object catch (e) {
                      throw StreamFailure(
                        StreamFailureCode.invalidArgument,
                        '$e',
                      );
                    }
                  }),
                  pauseSource: true,
                  limits: _dataLimits,
                  weigh: jsonWeight,
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
        return decodeDataStream(switch (kind) {
          'clientStream' => Stream.fromFuture(
            _client.uploadData(requests!, context),
          ),
          'bidiStream' => _client.exchangeData(requests!, context),
          _ => _client.openData(header),
        }).map((v) {
          try {
            return itemShape.fromJson(v);
          } on Object catch (e) {
            throw StreamFailure(StreamFailureCode.invalidArgument, '$e');
          }
        });
      },
      limits: _dataLimits,
      pauseSource: true,
      weigh: (v) => jsonWeight(itemShape.toJson(v)),
      cancel: lease.token,
      cancelFailure: () => lease.failure,
      onClosed: (_, _, _) {
        cancelled?.dispose();
        rpcCancel.cancel();
        _data.remove(lease);
        lease.token.cancel();
      },
    );
  }

  Stream<Object?> _receiveOwnerData(
    Stream<WireJson> requests,
    String kind,
    RpcContext? context,
  ) => receiveLeasedExchange(
    requests,
    (header, input, lease) =>
        _serveData(header, input: input, kind: kind, lifetime: lease),
    limits: _dataLimits,
    context: context,
    admit: (lease) {
      _mayOpenData(providing: true, kind: kind);
      _data[lease] = who;
      _providedData.add(lease);
    },
    release: (lease) {
      _data.remove(lease);
      _providedData.remove(lease);
    },
  );

  Stream<Object?> _serveData(
    Map<String, Object?> request, {
    Stream<Object?>? input,
    String kind = 'serverStream',
    StreamLease? lifetime,
  }) {
    final lease = StreamLease();
    IHandle? expiry;
    _DataSource? source;
    return boundedStream<Object?>(
      () {
        _mayOpenData(providing: true, kind: kind, reserved: lifetime != null);
        if (request['name'] is! String ||
            request['id'] is! String ||
            request['params'] is! Map ||
            request['cause'] is! Map ||
            (request['traceparent'] != null &&
                request['traceparent'] is! String)) {
          throw const StreamFailure(
            StreamFailureCode.invalidArgument,
            'a malformed stream opening',
          );
        }
        final Cause cause;
        try {
          cause = Cause.fromJson(request['cause']);
        } on Object catch (_) {
          throw const StreamFailure(
            StreamFailureCode.invalidArgument,
            'a malformed stream cause',
          );
        }
        final found = _streams[request['name']];
        if (found == null) {
          throw const StreamFailure(
            StreamFailureCode.unavailable,
            'the owner no longer provides the stream',
          );
        }
        if (found.d.kind != kind ||
            (found.d.input != null) != (input != null)) {
          throw const StreamFailure(
            StreamFailureCode.invalidArgument,
            'the owner provides a different stream type',
          );
        }
        source = found;
        expiry = lifetime?.token.onCancel(() => lease.end(lifetime.failure));
        _data[lifetime ?? lease] = found.as ?? who;
        _providedData.add(lifetime ?? lease);
        found.open.add(lease);
        final call = StreamCall(
          request['id']! as String,
          found.d.name,
          Kept.json((request['params']! as Map).cast<String, Object?>()),
          cause,
          lease.token,
          kind: kind,
          traceparent: request['traceparent'] as String?,
          input: input == null
              ? null
              : boundedStream<Object?>(
                  () => input,
                  pauseSource: true,
                  limits: _dataLimits,
                  weigh: jsonWeight,
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
        return contextualStream(found.handler, call);
      },
      limits: _dataLimits,
      pauseSource: true,
      weigh: jsonWeight,
      cancel: lease.token,
      cancelFailure: () => lease.failure,
      onClosed: (_, _, _) {
        source?.open.remove(lease);
        expiry?.dispose();
        if (lifetime == null) {
          _data.remove(lease);
          _providedData.remove(lease);
        }
        lease.token.cancel();
      },
    );
  }
}
