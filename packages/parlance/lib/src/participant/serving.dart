import 'dart:async';

import '../registry/cause.dart';
import '../registry/registry.dart' show CommandHandler;

/// What holds, in the zone code runs in, the cause of what it does: of a
/// principal, as it follows from the call or the fact being answered.
final Object _following = Object();

/// [f], run so that what is written, said and called in it with no cause
/// given follows from what [causeFor] says (SPEC §4), after an `await`
/// too, and in a timer it starts. A value in a zone, no more: it costs a
/// fraction of a microsecond.
R following<R>(Cause Function(Principal by) causeFor, R Function() f) =>
    runZoned(f, zoneValues: {_following: causeFor});

/// [handler], run following the call it serves: `call.causeFor(who)`.
CommandHandler serving(CommandHandler handler) =>
    (call) => following(call.causeFor, () => handler(call));

/// The cause of what [by] does with none given, where it runs: following
/// from the call or the fact being answered, if one is; else null.
Cause? inReplyAs(Principal by) =>
    (Zone.current[_following] as Cause Function(Principal)?)?.call(by);
