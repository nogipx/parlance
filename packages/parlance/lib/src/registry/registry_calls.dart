part of 'registry.dart';

/// Serves a command: answers its result (checked against `returns`), or
/// throws.
///
/// Returns `dynamic` so a handler that answers nothing needs no `return`.
typedef CommandHandler = FutureOr<dynamic> Function(CommandCall call);

/// Null when a command can run now, else why not (SPEC §6.2). Synchronous;
/// reads committed state.
typedef WhyNot = String? Function();

/// Null when [call] may go on, else why not (SPEC §10). Synchronous; reads
/// committed state; makes no calls.
typedef GuardCheck = String? Function(PendingCall call);

/// Where errors of guards and timers go.
typedef ErrorSink = void Function(Object error, StackTrace stack);

/// What a query's handler tried that would change something (SPEC §6.6):
/// a write, a fact, a command. Thrown where it was tried, so the
/// query ends `failed` and nothing changed.
final class QueryEffect extends StateError {
  QueryEffect(this.query, this.tried)
    : super('$query is a query, it changes nothing: it tried to $tried');

  final String query;
  final String tried;
}

const Symbol _asking = #parlance.asking;

/// Runs [body] as the handler of [query]: what it does through parlance,
/// at once or later (after an await, in a timer it started), is told to
/// be the query's, and refused when it would change something. Closures
/// still see everything they captured: what they try is refused, not
/// hidden. A remote participant serves its queries the same way.
R asQuery<R>(String query, R Function() body) =>
    runZoned(body, zoneValues: {_asking: query});

/// The query whose handler the code running now is ([asQuery]); null
/// outside one.
String? answeringQuery() => Zone.current[_asking] as String?;

/// Throws [QueryEffect] when the code running now is a query's handler
/// ([asQuery]): [tried] is what it would have done.
void refuseInQuery(String tried) {
  if (answeringQuery() case final query?) throw QueryEffect(query, tried);
}

/// A call being served: what a handler gets. The registry makes it; a
/// remote participant (SPEC §22.4) makes it of what the host sent.
final class CommandCall {
  CommandCall(
    this.id,
    this.command,
    Map<String, Object?> params,
    this.cause,
    this.expired, {
    LogSpanHandle? span,
  }) : _params = Kept.json(params),
       _answers = null,
       _span = span;

  CommandCall._kept(
    this.id,
    this.command,
    this._params,
    this.cause,
    this.expired,
    this._answers, {
    LogSpanHandle? span,
  }) : _span = span;

  final String id;
  final String command;

  /// As the command keeps them (SPEC §18).
  final Kept _params;

  /// The shape the answer is kept by, when the command keeps it as it is:
  /// then the handler answers the Dart value, else its JSON.
  final Shape<Object?>? _answers;

  /// Checked, with defaults filled; as JSON.
  Map<String, Object?> get params => _params.json! as Map<String, Object?>;
  final Cause cause;

  Principal get by => cause.by;

  /// Cancelled when the deadline passes or the caller cancels: it was
  /// answered `timedOut` or `cancelled`. What the handler does after still
  /// stands (and its end is recorded as late), so a handler that can stop
  /// stops here (`expired.isCancelled`), and gives it on as `cancel:` to
  /// what it calls in turn.
  final CancellationToken expired;

  /// The cause of what the handler does on behalf of [by]: nested calls
  /// and writes. Its parent is this call.
  Cause causeFor(Principal by) => cause.child(id, by: by, word: command);

  /// The span of this call in the registry's log (SPEC §9.2): what the
  /// handler logs in it, events and spans of its own, goes with the call
  /// and its trace. Without a log it is `LogScope.noop`'s, ended and
  /// keeping nothing; an event whose message or data costs something is
  /// built behind `span.isEnabled(level)`, false then.
  LogSpanHandle get span => _span ?? noSpan;
  final LogSpanHandle? _span;
}

/// The params of [call] as [shape] has them: the value itself when the
/// command keeps them by [shape], else their JSON decoded. The package's
/// own.
T paramsAs<T>(CommandCall call, Shape<T> shape) => call._params.asShape(shape);

/// Whether [call]'s handler answers the Dart value of [shape]: when the
/// command keeps its answer by it; else it answers JSON. The package's
/// own.
bool answersAs(CommandCall call, Shape<Object?>? shape) =>
    identical(call._answers, shape);

/// A call on its way, as guards see it.
final class PendingCall {
  PendingCall(this.id, this.command, Map<String, Object?> params, this.cause)
    : _params = Kept.json(params);

  PendingCall._kept(this.id, this.command, this._params, this.cause);

  final String id;

  /// The command's, or the query's, descriptor.
  final CallableDescriptor command;
  final Kept _params;

  /// Its params, checked, as JSON: made when a guard reads them.
  Map<String, Object?> get params => _params.json! as Map<String, Object?>;
  final Cause cause;

  Principal get by => cause.by;
}

final class _Guard {
  _Guard(this.id, this.check) : ask = null, timeout = null, judges = null;
  _Guard.asked(this.id, this.ask, this.timeout, this.judges) : check = null;
  final String id;
  final GuardCheck? check;

  /// A guard another judges, across a connection.
  final Future<String?> Function(PendingCall call)? ask;
  final Duration? timeout;

  /// Whether it judges calls of a command, known at once: one it does not
  /// is not asked, so the call waits for nothing.
  final bool Function(String command)? judges;
}

/// A call id seen within the dedup window, and the call it was given for.
final class _Seen {
  _Seen(this.at, this.command, this.params, this.by, this.result);
  final DateTime at;
  final String command;
  final Kept params;
  final Principal by;
  Future<CallResult<Object?>> result;
}
