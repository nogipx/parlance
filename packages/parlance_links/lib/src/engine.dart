import 'dart:async';

import 'package:parlance/participant.dart';
import 'package:parlance/registry.dart';

import 'model.dart';

/// A trigger of the owner's that links name by a key of their own
/// (`{chat: "!clip"}`): it stands for one of the triggers links know
/// ([translate]), and [accept] picks what of what that fired a run gets.
final class TriggerExtension {
  const TriggerExtension(this.name, {required this.translate, this.accept});

  /// The key that names it in a trigger.
  final String name;

  /// The trigger it stands for, of the link's trigger object; throws
  /// [FormatException] when the object is not one of it. Its throttles
  /// hold unless the link says its own.
  final Trigger Function(Map<String, Object?> options) translate;

  /// The data a run gets of [data], what the trigger fired with; null: it
  /// does not run. Without it, the data as it came.
  final Object? Function(Object? data, Map<String, Object?> options)? accept;
}

/// A link that could not be taken, and why.
final class LinkProblem {
  const LinkProblem(this.link, this.message);

  /// Its id, or its place in the list when it has none.
  final String link;
  final String message;

  @override
  String toString() => '$link: $message';
}

/// A run that ended: [why] it stopped short, or null when it did all.
final class LinkRun {
  const LinkRun(this.link, this.data, this.why);
  final Link link;
  final Object? data;
  final String? why;
}

/// The links of one participant, run as it: what they call, they call as
/// [participant], with its rights and no more, so a link may do exactly
/// what its owner may.
///
/// The owner's buttons go in its [vocabulary]: the state
/// `<vocabulary>.links.buttons` (how each looks now; meta `buttons: true`,
/// and `press`: the command that presses one)
/// and the command `<vocabulary>.links.press`, which [pressers] may call.
final class Links {
  Links(
    this.participant, {
    required this.vocabulary,
    Callers? pressers,
    List<TriggerExtension> extensions = const [],
    this.onError,
    this.onRun,
    this.conversationLimit = 16,
  }) : pressers = pressers ?? Callers({'*': Access.allow}),
       _extensions = {for (final e in extensions) e.name: e};

  final IParticipant participant;
  final String vocabulary;
  final Callers pressers;
  final Map<String, TriggerExtension> _extensions;
  final ErrorSink? onError;

  /// Told of every run that ended.
  final void Function(LinkRun run)? onRun;

  /// How many runs one conversation may start: what follows from one
  /// message ends there, so links that set each other off stop.
  final int conversationLimit;

  List<Link> _links = const [];
  List<LinkProblem> _problems = const [];
  final Map<String, _Active> _active = {};
  final Map<String, int> _conversations = {};
  final List<StreamSubscription<Object?>> _watching = [];
  IStateHandle? _buttons;
  IHandle? _press;
  List<Object?> _shown = const [];
  bool _disposed = false;

  String get buttonsState => '$vocabulary.links.buttons';
  String get pressCommand => '$vocabulary.links.press';

  /// The links taken, in order.
  List<Link> get links => _links;

  /// What the last [load] could not take.
  List<LinkProblem> get problems => _problems;

  /// Takes [json] as all its links, in place of those it had: each link
  /// that cannot be taken is told in [problems] and left out, the others
  /// run. Completes once the states they read are known.
  Future<void> load(List<Object?> json) async {
    _stop();
    final links = <Link>[];
    final problems = <LinkProblem>[];
    final ids = <String>{};
    for (final (i, j) in json.indexed) {
      final at = j is Map && j['id'] is String ? j['id']! as String : '#$i';
      try {
        final link = Link.parse(j);
        if (!ids.add(link.id)) throw FormatException('id ${link.id} twice');
        for (final t in link.triggers) {
          if (t is ExtensionTrigger) _resolve(t);
        }
        links.add(link);
      } on FormatException catch (e) {
        problems.add(LinkProblem(at, e.message));
      }
    }
    _links = List.unmodifiable(links);
    _problems = List.unmodifiable(problems);
    final reads = {
      for (final l in links)
        if (l.enabled) ...{...?l.only?.reads, ...?l.button?.lit?.reads},
    };
    await Future.wait([
      for (final s in reads) participant.fetch(s).then((_) {}, onError: _err),
    ]);
    if (_disposed) return;
    _defineButtons();
    if (reads.isNotEmpty) {
      _watching.add(
        participant.changes(reads).listen((_) => _showButtons(), onError: _err),
      );
    }
    for (final c in {
      for (final l in links)
        if (l.button != null) ..._firstCall(l).map((s) => s.command),
    }) {
      _watching.add(
        participant
            .statusChanges(c)
            .listen((_) => _showButtons(), onError: _err),
      );
    }
    for (final l in links) {
      if (l.enabled) _active[l.id] = _Active(this, l)..start();
    }
    _showButtons();
  }

  /// Presses button [id], as the cause of [cause] (the press command's
  /// call): null when its run did all, else why not.
  Future<String?> press(String id, {Cause? cause, String? callId}) async {
    final a = _active[id];
    if (a == null || a.link.button == null) return 'no button $id';
    return a.fire(
      a.link.button!,
      const <String, Object?>{},
      cause: cause,
      id: callId,
      wait: true,
    );
  }

  /// How each button looks now, in the order of the links: what
  /// `<vocabulary>.links.buttons` holds.
  List<Map<String, Object?>> buttons() => [
    for (final l in _links)
      if (l.button case final b? when l.enabled) _look(l, b),
  ];

  Map<String, Object?> _look(Link l, ButtonTrigger b) {
    final lit = b.lit == null ? null : _holds(b.lit!);
    final look = b.look;
    return {
      'id': l.id,
      for (final e in look.entries)
        if (e.key != 'litLabel' && e.key != 'label') e.key: e.value,
      'label': lit == true && look['litLabel'] is String
          ? look['litLabel']
          : look['label'],
      'lit': ?lit,
      'unavailable': ?_unavailable(l),
    };
  }

  /// Why [l] cannot run now, or null.
  String? _unavailable(Link l) {
    if (l.only case final only? when !_holds(only)) return 'only when $only';
    for (final s in _firstCall(l)) {
      switch (participant.status(s.command)) {
        case WordReady():
          break;
        case WordUnavailable(:final why):
          return why;
        case final other:
          return '${s.command}: $other';
      }
    }
    return null;
  }

  /// The first call of [l], the one a button stands for.
  static Iterable<CallStep> _firstCall(Link l) =>
      l.steps.whereType<CallStep>().take(1);

  void _defineButtons() {
    final any = _links.any((l) => l.enabled && l.button != null);
    if (!any) return;
    _buttons = participant.defineState(
      StateDescriptor(
        buttonsState,
        type: const ListType(AnyType()),
        meta: {'buttons': true, 'press': pressCommand, 'label': 'Buttons'},
      ),
    );
    _press = participant.defineCommand(
      CommandDescriptor(
        pressCommand,
        params: const ObjectType({'button': Field(TextType())}),
        callers: pressers,
        deadline: const Duration(minutes: 2),
        meta: const {'label': 'Press a button'},
      ),
      (call) async {
        final why = await press(
          call.params['button']! as String,
          cause: call.cause,
          callId: call.id,
        );
        if (why != null) throw StateError(why);
      },
    );
  }

  void _showButtons() {
    final h = _buttons;
    if (h == null || _disposed) return;
    final now = buttons();
    if (jsonEquals(now, _shown)) return;
    _shown = now;
    h.set(now);
  }

  /// The trigger an extension's stands for.
  Trigger _resolve(ExtensionTrigger t) {
    final e = _extensionOf(t);
    return e.translate(t.raw);
  }

  TriggerExtension _extensionOf(ExtensionTrigger t) {
    for (final k in t.raw.keys) {
      if (_extensions[k] case final e?) return e;
    }
    throw FormatException('no trigger ${t.raw.keys.join(', ')}');
  }

  bool _holds(Condition c) => switch (c) {
    StateIs(:final state, :final key, :final test) => test.matches(
      participant.read(state, key: key),
    ),
    AllOf(:final all) => all.every(_holds),
    AnyOf(:final any) => any.any(_holds),
  };

  /// Whether one more run may start in conversation [id].
  bool _mayStart(String id) {
    final n = (_conversations[id] ?? 0) + 1;
    if (n > conversationLimit) return false;
    _conversations.remove(id);
    _conversations[id] = n;
    while (_conversations.length > 256) {
      _conversations.remove(_conversations.keys.first);
    }
    return true;
  }

  void _err(Object e, [StackTrace? st]) =>
      onError?.call(e, st ?? StackTrace.current);

  void _stop() {
    for (final a in _active.values) {
      a.stop();
    }
    _active.clear();
    for (final s in _watching) {
      unawaited(s.cancel());
    }
    _watching.clear();
    _buttons?.dispose();
    _buttons = null;
    _press?.dispose();
    _press = null;
    _shown = const [];
  }

  /// Stops every link; what runs now stops at its next step.
  Future<void> dispose() async {
    _disposed = true;
    _stop();
  }
}

/// A link that runs: its triggers heard, its runs one at a time.
final class _Active {
  _Active(this.links, this.link);

  final Links links;
  final Link link;
  final List<StreamSubscription<Object?>> _subs = [];
  final Set<Timer> _timers = {};
  final Map<String, DateTime> _throttled = {};

  /// The runs waiting their turn, each with what tells its end.
  final List<(void Function(), Completer<String?>)> _queue = [];
  bool _running = false;
  bool _stopped = false;

  /// Completes when the link stops: a run waiting in a step ends then.
  final Completer<void> _halt = Completer();

  IParticipant get _p => links.participant;

  void start() {
    for (final t in link.triggers) {
      if (t is ExtensionTrigger) {
        final e = links._extensionOf(t);
        final base = e.translate(t.raw);
        _hear(
          base,
          as: t.throttles.isEmpty ? base.throttles : t.throttles,
          accept: e.accept == null ? null : (d) => e.accept!(d, t.raw),
        );
      } else {
        _hear(t, as: t.throttles);
      }
    }
  }

  void _hear(
    Trigger t, {
    required List<Throttle> as,
    Object? Function(Object? data)? accept,
  }) {
    void fireWith(Object? data, {Cause? cause, String? id}) {
      final d = accept == null ? data : accept(data);
      if (d == null) return;
      unawaited(fire(t, d, cause: cause, id: id, throttles: as));
    }

    switch (t) {
      case FactTrigger(:final fact, :final where):
        _subs.add(
          _p.facts(fact).listen((m) {
            if (where.matches(m.payload)) {
              fireWith(m.payload, cause: m.cause, id: m.id);
            }
          }, onError: links._err),
        );
      case StateTrigger():
        _watchState(t, fireWith);
      case EveryTrigger(:final interval):
        _timers.add(
          Timer.periodic(interval, (_) => fireWith(<String, Object?>{})),
        );
      case ButtonTrigger():
        break;
      case ExtensionTrigger():
        throw StateError('an extension stands for one links know');
    }
  }

  void _watchState(
    StateTrigger t,
    void Function(Object? data, {Cause? cause, String? id}) fireWith,
  ) {
    var seen = false;
    Object? previous;
    Timer? holding;
    void fireNow(Object? before, Object? value) => fireWith({
      'state': t.state,
      'key': ?t.key,
      'value': value,
      'previous': before,
    });
    void fires(Object? before, Object? value) {
      if (holding case final h?) {
        h.cancel();
        _timers.remove(h);
      }
      holding = null;
      final hold = t.holdFor;
      if (hold == null) return fireNow(before, value);
      late final Timer timer;
      timer = Timer(hold, () {
        _timers.remove(timer);
        holding = null;
        fireNow(before, value);
      });
      _timers.add(holding = timer);
    }

    _subs.add(
      _p.watch(t.state, key: t.key).listen((value) {
        final before = previous;
        previous = value;
        if (holding case final h? when !t.holds(value)) {
          h.cancel();
          _timers.remove(h);
          holding = null;
        }
        if (!seen) {
          seen = true;
          if (t.already && value != null && t.holds(value)) {
            fires(null, value);
          }
          return;
        }
        if (value == null) return;
        if (before == null) {
          // A value come where there was none is no change.
          if (t.already && t.holds(value)) fires(null, value);
          return;
        }
        if (t.fires(before, value)) fires(before, value);
      }, onError: links._err),
    );
  }

  /// Fires the link with [data], from the message [id] of [cause]: it
  /// runs unless a throttle, its only or its mode hold it back. With
  /// [wait], answers when the run ended: null when it did all, else why
  /// not; else at once.
  Future<String?> fire(
    Trigger t,
    Object? data, {
    Cause? cause,
    String? id,
    List<Throttle>? throttles,
    bool wait = false,
  }) async {
    if (_stopped) return 'stopped';
    final now = _p.clock.now();
    final keys = <String>[];
    for (final (i, th) in (throttles ?? t.throttles).indexed) {
      final key = '$i:${th.per == null ? '' : jsonAt(data, th.per!)}';
      final last = _throttled[key];
      if (last != null && now.difference(last) < th.every) {
        return 'not again so soon';
      }
      keys.add(key);
    }
    if (link.only case final only? when !links._holds(only)) {
      return 'only when $only';
    }
    final conversation = id == null ? null : cause?.conversationOf(id) ?? id;
    if (conversation != null && !links._mayStart(conversation)) {
      links._err(
        StateError(
          'link ${link.id}: more than ${links.conversationLimit} runs '
          'followed from $conversation; stopped',
        ),
      );
      return 'too many runs from one message';
    }
    if (_running) {
      if (link.mode == RunMode.single) return 'already running';
      if (_queue.length >= link.queueLimit) return 'its queue is full';
    }
    for (final k in keys) {
      _throttled[k] = now;
    }
    final done = Completer<String?>();
    void go() => unawaited(_run(data, id, conversation, done));
    if (_running) {
      _queue.add((go, done));
    } else {
      go();
    }
    return wait ? done.future : null;
  }

  Future<void> _run(
    Object? data,
    String? parent,
    String? conversation,
    Completer<String?> done,
  ) async {
    _running = true;
    String? why;
    try {
      why = await _steps(data, parent, conversation);
    } on Object catch (e, st) {
      why = '$e';
      links._err(e, st);
    }
    _running = false;
    if (!done.isCompleted) done.complete(why);
    links.onRun?.call(LinkRun(link, data, why));
    if (_queue.isNotEmpty && !_stopped) _queue.removeAt(0).$1();
  }

  Future<String?> _steps(
    Object? data,
    String? parent,
    String? conversation,
  ) async {
    final cause = parent == null
        ? null
        : Cause(_p.who, parent: parent, conversation: conversation);
    final calls = link.steps.length;
    for (final (i, s) in link.steps.indexed) {
      if (_stopped) return 'stopped';
      switch (s) {
        case WaitStep(:final duration):
          // Stopping ends the wait: a run is not held for its whole
          // length by a link that is gone.
          final waited = Completer<void>();
          final timer = Timer(duration, waited.complete);
          _timers.add(timer);
          await Future.any([waited.future, _halt.future]);
          timer.cancel();
          _timers.remove(timer);
          if (_stopped) return 'stopped';
        case CallStep(:final command, :final params, :final orContinue):
          final r = await _p.call(
            command,
            _resolve(params, data),
            cause: cause,
          );
          if (r is CallDone || orContinue) continue;
          final whyNot = r.whyNot ?? '$r';
          return calls == 1
              ? whyNot
              : 'step ${i + 1} of $calls ($command)'
                    '${i == 0 ? '' : ', after ${i == 1 ? 'step 1' : 'steps 1-$i'} done'}'
                    ': $whyNot';
      }
    }
    return null;
  }

  /// [v] with each `$trigger.<path>` the value at that path in [data].
  static Object? _resolveValue(Object? v, Object? data) => switch (v) {
    final String s when s == r'$trigger' => data,
    final String s when s.startsWith(r'$trigger.') => jsonAt(
      data,
      s.substring(9),
    ),
    final Map<Object?, Object?> m => {
      for (final e in m.entries) '${e.key}': _resolveValue(e.value, data),
    },
    final List<Object?> l => [for (final x in l) _resolveValue(x, data)],
    _ => v,
  };

  static Map<String, Object?> _resolve(
    Map<String, Object?> params,
    Object? data,
  ) => {for (final e in params.entries) e.key: ?_resolveValue(e.value, data)};

  void stop() {
    _stopped = true;
    if (!_halt.isCompleted) _halt.complete();
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    for (final t in [..._timers]) {
      t.cancel();
    }
    // What waited its turn is told it will not run: a press waiting on it
    // (a command's call) ends, rather than hold the call to its deadline.
    for (final (_, done) in _queue) {
      if (!done.isCompleted) done.complete('stopped');
    }
    _queue.clear();
  }
}
