import 'dart:async';

/// What cancels calls when its holder says so: given as `cancel:` to a
/// client or a call, whose calls still waiting then answer `cancelled`
/// (`CallCancelled`). Cancelled once, it stays so; cancelled before a call
/// is made, that call does not run.
///
/// ```dart
/// final stop = CancellationToken();
/// final player = IPlayerClient(participant, cancel: stop);
/// ...
/// stop.cancel();
/// ```
final class CancellationToken {
  CancellationToken();

  final Completer<void> _cancelled = Completer();

  /// Whether it was cancelled.
  bool get isCancelled => _cancelled.isCompleted;

  /// Completes when it is cancelled.
  Future<void> get whenCancelled => _cancelled.future;

  /// Cancels what it was given to; again, nothing more.
  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }
}
