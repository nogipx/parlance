import 'dart:async';

import '../core/core.dart' show Disposer, IHandle;

/// What cancels a call when its holder says so: given as `cancel:` to a
/// call, which then answers `cancelled` (`CallCancelled`) if it is still
/// waited for. Cancelled once, it stays so; cancelled before a call is
/// made, that call does not run. One token given to several calls cancels
/// them together, and holds nothing of a call once it ended.
///
/// ```dart
/// final stop = CancellationToken();
/// final found = player.search(text: 'x', cancel: stop);
/// ...
/// stop.cancel();
/// ```
final class CancellationToken {
  /// A new token, not cancelled.
  CancellationToken();

  bool _cancelled = false;
  Completer<void>? _when;
  final Map<Object, void Function()> _onCancel = {};

  /// Whether it was cancelled.
  bool get isCancelled => _cancelled;

  /// Completes when it is cancelled. Waited for, it is held until then:
  /// what listens for as long as something else lasts uses [onCancel].
  Future<void> get whenCancelled {
    final when = _when ??= Completer();
    if (_cancelled && !when.isCompleted) when.complete();
    return when.future;
  }

  /// Runs [f] when it is cancelled, at once if it was, until the handle is
  /// disposed: then it holds nothing of [f].
  IHandle onCancel(void Function() f) {
    if (_cancelled) {
      f();
      return Disposer(() {});
    }
    final key = Object();
    _onCancel[key] = f;
    return Disposer(() => _onCancel.remove(key));
  }

  /// Cancels what it was given to; again, nothing more.
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _when?.complete();
    final fs = [..._onCancel.values];
    _onCancel.clear();
    for (final f in fs) {
      try {
        f();
      } on Object catch (e, s) {
        Zone.current.handleUncaughtError(e, s);
      }
    }
  }
}

/// [work]'s value, or [orElse]'s when [cancel] is cancelled first: [work]
/// goes on unwaited, an error of it caught. [cancel] holds nothing of it
/// once either came. The package's own.
Future<T> untilCancelled<T>(
  Future<T> work,
  CancellationToken? cancel,
  T Function() orElse,
) {
  if (cancel == null) return work;
  final done = Completer<T>();
  final heard = cancel.onCancel(() {
    if (!done.isCompleted) done.complete(orElse());
  });
  work.then(
    (v) {
      heard.dispose();
      if (!done.isCompleted) done.complete(v);
    },
    onError: (Object e, StackTrace s) {
      heard.dispose();
      if (!done.isCompleted) done.completeError(e, s);
    },
  );
  return done.future;
}
