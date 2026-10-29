import 'dart:async';

import '../registry/cause.dart';
import '../registry/registry.dart' show CommandHandler;

/// What the zone code runs in holds of what it answers: the cause of what
/// a principal does there, and on whose behalf what it answers came.
typedef _Answering = ({Cause Function(Principal by) causeFor, Principal by});

final Object _answering = Object();

/// [f], run so that what is written, said and called in it with no cause
/// given follows from what [causeFor] says (SPEC §4), after an `await`
/// too, and in a timer it starts; [by] is on whose behalf what it answers
/// came. A value in a zone, no more: it costs a fraction of a microsecond.
R following<R>(
  Cause Function(Principal by) causeFor,
  Principal by,
  R Function() f,
) => runZoned(f, zoneValues: {_answering: (causeFor: causeFor, by: by)});

/// [f], run as nothing's answer: what it does there is its own act.
R apart<R>(R Function() f) => runZoned(f, zoneValues: {_answering: null});

/// [handler], run following the call it serves: `call.causeFor(who)`.
CommandHandler serving(CommandHandler handler) =>
    (call) => following(call.causeFor, call.by, () => handler(call));

_Answering? get _now => Zone.current[_answering] as _Answering?;

/// The cause of what [by] does with none given, where it runs: following
/// from the call or the fact being answered, if one is; else null.
Cause? inReplyAs(Principal by) => _now?.causeFor(by);

/// On whose behalf the call or the fact being answered came, where it
/// runs; null where nothing is being answered.
Principal? get answering => _now?.by;
