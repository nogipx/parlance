part of 'participant.dart';

final class _Command {
  _Command(this.d, this.handler, this.available, this.as);

  /// A command's or a query's.
  final CallableDescriptor d;
  final CommandHandler handler;
  final Availability? available;

  /// The part that defined it; null for the participant itself.
  final Principal? as;

  /// What its check said last, told to the host.
  String? why;
  bool told = false;
}

final class _State implements IStateHandle {
  _State(this._p, this.descriptor, this._by);
  final RemoteParticipant _p;

  /// The part that defined it; null for the participant itself.
  final Principal? _by;

  @override
  final StateDescriptor descriptor;

  /// It goes across as JSON.
  @override
  Shape<Object?>? get shape => null;

  @override
  void set(Object? value, {String? key, Cause? cause}) {
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

  @override
  void remove({String? key, Cause? cause}) {
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
  _Fact(this._p, this.descriptor, {required this.own, Principal? as})
    : _by = as;
  final RemoteParticipant _p;
  final bool own;

  /// The part that says it; null for the participant itself.
  final Principal? _by;

  @override
  final FactDescriptor descriptor;

  /// It goes across as JSON.
  @override
  Shape<Object?>? get shape => null;

  /// Says [payload]. True: whether the registry took it (a repeat of [id]
  /// is dropped there) is not known when it is said.
  @override
  bool emit(Object? payload, {String? id, Cause? cause}) {
    final speaker = _by ?? _p.who;
    cause ??= inReplyAs(speaker);
    final by = cause != null && !_p._ownAct(cause.by, speaker)
        ? cause.by
        : null;
    // Another's fact is held to its type as the catalog says it now, as
    // far as the copy knows it: refused here, as in the host's process.
    final type = own
        ? descriptor.type
        : switch (_p._mirror.descriptorOf(descriptor.name)) {
            final FactDescriptor d => d.type,
            _ => descriptor.type,
          };
    _p._ask({
      'op': 'emit',
      'fact': descriptor.name,
      'payload': freezeJson(type.check(payload, const _Unseen())),
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
    if (!own || _p._facts.remove(descriptor.name) == null) return;
    _p._ask({'op': 'undefine', 'name': descriptor.name});
  }
}

/// What a value is checked against before it is sent: its type, as the
/// host checks it. Entities and the host's own types are the host's to
/// know: they pass here, and the host checks them.
final class _Unseen implements ITypeContext {
  const _Unseen();

  @override
  bool hasKind(String kind) => true;

  @override
  bool hasEntity(String kind, String id) => true;

  @override
  String? checkCustom(String name, Object? value) => null;
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
}
