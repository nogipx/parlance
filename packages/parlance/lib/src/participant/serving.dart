import 'dart:async';

import '../registry/cause.dart';
import '../registry/registry.dart' show CommandCall, CommandHandler;

/// What holds, in the zone a handler runs in, the call it serves.
final Object _served = Object();

/// [handler], run in a zone that holds the call it serves (SPEC §4): what
/// it writes, says and calls with no cause given follows from that call,
/// after an `await` too, as `call.causeFor(who)` would make it. A value in
/// a zone, no more: it costs a fraction of a microsecond a call.
CommandHandler serving(CommandHandler handler) =>
    (call) => runZoned(() => handler(call), zoneValues: {_served: call});

/// The cause of what [by] does with none given, where it runs: following
/// from the call being served, if one is; else null.
Cause? inReplyAs(Principal by) =>
    (Zone.current[_served] as CommandCall?)?.causeFor(by);
