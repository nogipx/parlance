import 'package:clock/clock.dart' show Clock;

import '../core/core.dart';
import 'cause.dart';
import 'messages.dart';

/// Who used each word, by the name used (SPEC §6.8): calls and asks, reads
/// and listeners from outside the build. Only a name there is a word of
/// (or an old name of one) is counted, so a peer's made-up names keep
/// nothing; for one word at most [perWord] principals are told apart, the
/// rest counted under their kind alone.
final class WordUses {
  WordUses({
    required bool Function(String name) isWord,
    required this.perWord,
    required Clock clock,
  }) : _isWord = isWord,
       _clock = clock;

  final bool Function(String name) _isWord;
  final int perWord;
  final Clock _clock;
  final Map<String, Map<Principal, _Use>> _uses = {};

  /// The record of [by]'s use of [name]; null for a name no word is of.
  _Use? _of(String name, Principal by) {
    if (!_isWord(name)) return null;
    final users = _uses.putIfAbsent(name, () => {});
    final who = users.containsKey(by) || users.length < perWord
        ? by
        : Principal(by.kind);
    return (users[who] ??= _Use(who, _clock))..seen();
  }

  /// [by] called or asked [name].
  void called(String name, Principal by) => _of(name, by)?.called();

  /// [by] read [name] once, from outside the build.
  void read(String name, Principal by) => _of(name, by)?.read();

  /// [by] listens to [name] until the handle is disposed; null for a name
  /// no word is of.
  IHandle? listening(String name, Principal by) {
    final use = _of(name, by);
    if (use == null) return null;
    use.listening++;
    return Disposer(() => use.listening--);
  }

  /// Who used [name], as it was named.
  List<WordUse> of(String name) => [
    for (final u in (_uses[name] ?? const {}).values) u.snapshot(),
  ];

  /// Every name used, and by whom.
  Map<String, List<WordUse>> get all => {
    for (final name in _uses.keys) name: of(name),
  };

  /// What was counted of [name], a name that is no longer a word nor an
  /// old name of one: there is nothing left to remove that a count would
  /// warn of. Who listens to it now stays, so a word defined again under
  /// it (a plugin reloaded) goes on counting them.
  void forget(String name) {
    final users = _uses[name];
    if (users == null) return;
    users.removeWhere((_, u) => u.listening == 0);
    if (users.isEmpty) _uses.remove(name);
  }
}

final class _Use {
  _Use(this.by, this._clock);
  final Principal by;
  final Clock _clock;
  int calls = 0;
  int reads = 0;
  int listening = 0;
  DateTime? last;

  void seen() => last = _clock.now();
  void called() => calls++;
  void read() => reads++;

  WordUse snapshot() => WordUse(
    by: by,
    calls: calls,
    reads: reads,
    listening: listening,
    last: last!,
  );
}
