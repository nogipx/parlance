import 'dart:async';

import '../registry/cause.dart';
import '../registry/registry.dart' show CancellationToken, CommandHandler;

/// What the zone code runs in holds of what it answers: the cause of what
/// a principal does there, on whose behalf what it answers came, and when
/// the call it serves expired (none for a fact).
typedef _Answering = ({
  Cause Function(Principal by) causeFor,
  Principal by,
  _Expiry? expired,
});

/// The expiry of the call served where code runs, as the handler's own
/// token: made when first asked for, cancelled when the call expires.
final class _Expiry {
  _Expiry(this._of);
  final CancellationToken _of;

  late final CancellationToken token = () {
    final t = CancellationToken();
    _of.onCancel(t.cancel);
    return t;
  }();
}

final Object _answering = Object();

/// [f], run so that what is written, said and called in it with no cause
/// given follows from what [causeFor] says (SPEC §4), after an `await`
/// too, and in a timer it starts; [by] is on whose behalf what it answers
/// came; [expired], when the call it serves expired. A value in a zone,
/// no more: it costs a fraction of a microsecond.
R following<R>(
  Cause Function(Principal by) causeFor,
  Principal by,
  R Function() f, {
  CancellationToken? expired,
}) => runZoned(
  f,
  zoneValues: {
    _answering: (
      causeFor: causeFor,
      by: by,
      expired: expired == null ? null : _Expiry(expired),
    ),
  },
);

/// [f], run as nothing's answer: what it does there is its own act.
R apart<R>(R Function() f) => runZoned(f, zoneValues: {_answering: null});

/// [handler], run following the call it serves: `call.causeFor(who)`, and
/// its expiry where it runs ([answerExpired]).
CommandHandler serving(CommandHandler handler) =>
    (call) => following(
      call.causeFor,
      call.by,
      () => handler(call),
      expired: call.expired,
    );

_Answering? get _now => Zone.current[_answering] as _Answering?;

/// The cause of what [by] does with none given, where it runs: following
/// from the call or the fact being answered, if one is; else null.
Cause? inReplyAs(Principal by) => _now?.causeFor(by);

/// On whose behalf the call or the fact being answered came, where it
/// runs; null where nothing is being answered.
Principal? get answering => _now?.by;

/// The token of the call being served where it runs, cancelled when the
/// call expires: its caller cancelled it, or its deadline passed. One per
/// call. Null where no call is served.
CancellationToken? get answerExpired => _now?.expired?.token;

/// Where an owner's words are being defined, told of each keyed state
/// defined there and the choices its keys are of: what goes of them goes
/// of the state too ([OwnerTools.choices]).
final Object keyedDefined = Object();

final Object _once = Object();

final class _Once {
  _Once(this.id);
  final String id;
  bool said = true;
}

/// Runs [say], what it says said under [id] (SPEC §8): said again under
/// the same id, the registry drops it. False when it was dropped so, in
/// the host's process; across a connection the host drops it, and this
/// is true. For what comes from outside more than once (a platform's
/// event, a webhook retried).
bool once(String id, void Function() say) {
  final o = _Once(id);
  runZoned(say, zoneValues: {_once: o});
  return o.said;
}

/// The id what is said here is said under ([once]); null outside it.
String? get onceId => (Zone.current[_once] as _Once?)?.id;

/// What was said here under [onceId] was dropped as said before.
void droppedOnce() => (Zone.current[_once] as _Once?)?.said = false;
