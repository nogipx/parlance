part of 'participant.dart';

final class _Command {
  _Command(this.d, this.handler, this.whyNot, this.as);

  /// A command's or a query's.
  final CallableDescriptor d;
  final CommandHandler handler;
  final WhyNot? whyNot;

  /// The owner that defined it; null for the participant itself.
  final Principal? as;

  /// What its check said last, told to the host.
  String? why;
  bool told = false;
}

final class _State implements IStateHandle {
  _State(this._p, this.descriptor, this._by);
  final RemoteParticipant _p;

  /// The owner that defined it; null for the participant itself.
  final Principal? _by;

  @override
  final StateDescriptor descriptor;

  /// It goes across as JSON.
  @override
  Shape<Object?>? get shape => null;

  @override
  void set(Object? value, {String? key, Cause? cause}) {
    // What a participant gone writes is not written, nor what an owner
    // withdrawn writes of a word it no longer has: code still running when
    // it went is let go quietly, as in the host's process.
    if (_gone) return;
    final c = _p._as(cause, _by);
    _checkKey(key);
    // Refused here, as in the host's process, not later in errors.
    final v = freezeJson(descriptor.type.check(value, const _Unseen()));
    _p._ask({
      'op': 'set',
      'state': descriptor.name,
      'key': ?key,
      'value': v,
      ...RemoteParticipant._causeOf(c),
      ...RemoteParticipant._asOf(_by),
    });
    _p._changing(descriptor.name, key);
    (_p._own[descriptor.name] ??= {})[key] = v;
  }

  /// Whether it writes no more: its participant went, or it was withdrawn
  /// (disposed, or its owner was).
  bool get _gone =>
      _p._disposed || !identical(_p._states[descriptor.name]?.d, descriptor);

  @override
  void remove({String? key, Cause? cause}) {
    if (_gone) return;
    final c = _p._as(cause, _by);
    _checkKey(key);
    _p._ask({
      'op': 'remove',
      'state': descriptor.name,
      'key': ?key,
      ...RemoteParticipant._causeOf(c),
      ...RemoteParticipant._asOf(_by),
    });
    _p._changing(descriptor.name, key);
    _p._own[descriptor.name]?.remove(key);
  }

  void _checkKey(String? key) {
    if (descriptor.keyed && (key == null || key.isEmpty)) {
      throw ArgumentError(
        '${descriptor.name} is keyed by ${descriptor.key}: give a key',
      );
    }
    if (!descriptor.keyed && key != null) {
      throw ArgumentError('${descriptor.name} has no keys');
    }
  }

  @override
  void dispose() {
    _p._states.remove(descriptor.name);
    if (_p._own.remove(descriptor.name) == null) return;
    _p._ask({'op': 'undefine', 'name': descriptor.name});
  }
}

final class _Fact implements IFactHandle {
  _Fact(this._p, this.descriptor, {Principal? as}) : _by = as;
  final RemoteParticipant _p;

  /// The owner that says it; null for the participant itself.
  final Principal? _by;

  @override
  final FactDescriptor descriptor;

  /// It goes across as JSON.
  @override
  Shape<Object?>? get shape => null;

  /// Says [payload]. True: whether the registry took it (a repeat of [id]
  /// is dropped there) is not known when it is said.
  @override
  bool say(Object? payload, {String? id, Cause? cause}) {
    // Gone, or withdrawn with its owner: said nowhere, as in the host's
    // process.
    if (_p._disposed || !identical(_p._facts[descriptor.name]?.d, descriptor)) {
      return false;
    }
    final speaker = _by ?? _p.who;
    cause ??= inReplyAs(speaker);
    final by = cause != null && !_p._ownAct(cause.by, speaker)
        ? cause.by
        : null;
    _p._ask({
      'op': 'emit',
      'fact': descriptor.name,
      'payload': freezeJson(descriptor.type.check(payload, const _Unseen())),
      // Its id is given here, so a fact sent again after a drop is dropped
      // by the host if it took it before.
      'id': id ?? newId(),
      'by': ?by?.toJson(),
      ...RemoteParticipant._causeOf(cause),
      ...RemoteParticipant._asOf(_by),
    });
    return true;
  }

  @override
  void dispose() {
    if (_p._facts.remove(descriptor.name) == null) return;
    _p._ask({'op': 'undefine', 'name': descriptor.name});
  }
}

/// What a value is checked against before it is sent: its type, as the
/// host checks it. Choices are the host's to
/// know: they pass here, and the host checks them.
final class _Unseen implements ITypeContext {
  const _Unseen();

  @override
  bool hasChoices(String name) => true;

  @override
  bool hasChoice(String name, String id) => true;
}

final class _Served extends ParlanceOwnerContractPeer {
  _Served(super.endpoint, this._p);
  final RemoteParticipant _p;

  @override
  Future<WireServed> onServe(WireServe request, {RpcContext? context}) =>
      _p._serve(request);

  @override
  Future<WireJson> onJudge(WireJson request, {RpcContext? context}) async =>
      _p._judge(request.json);

  @override
  Future<RpcNull> onExpire(WireName request, {RpcContext? context}) async {
    _p._expire(request.name);
    return const RpcNull();
  }
}
