import 'package:clock/clock.dart' show Clock;

import '../registry/cause.dart';
import '../registry/descriptors.dart';
import '../registry/registry.dart';
import '../registry/words.dart';
import 'local.dart';
import 'participant.dart';

/// The words of an app in one process, keeping nothing past what is now
/// (SPEC §22.5): the light way in, and a step from [Registry].
///
/// It makes participants as a [Registry] does, with the same
/// `participant(who, vocabularies:, rights:, access:)`, and they are the
/// same [LocalParticipant]s held to the same rules: vocabularies, callers
/// and readers, types, availability, guards, causes, ticks. What it does
/// not do is remember and tell: no ticks to resume a feed from, no call
/// records, no recent facts, so `explain` has no trail and `recent` is
/// empty; and its participants are not served across a connection. Its
/// commands are anyone's to call unless a word or a participant says
/// otherwise; a [Registry] asks who.
///
/// Moving to a [Registry] is `LocalRegistry()` made `Registry()`, and who
/// may call the commands said: the owners, the words and the parts that
/// use them do not change.
final class LocalRegistry {
  LocalRegistry({Clock? clock, ErrorSink? onError})
    : _r = Registry(
        retainTicks: 0,
        recentPerFact: 0,
        retainBytes: 0,
        clock: clock,
        onError: onError,
      ) {
    keepsNothing[_r] = true;
  }

  final Registry _r;

  /// Anyone may call a command no word and no participant names callers
  /// for.
  static const _open = WordAccess(call: Callers({'*': Access.allow}));

  /// A participant speaking as [who], defining words only in its
  /// [vocabularies], as `Registry.participant` makes one (SPEC §22.1);
  /// its commands are anyone's to call unless [access] or a word says.
  LocalParticipant participant(
    Principal who, {
    Iterable<WordSet> vocabularies = const [],
    ParticipantRights rights = ParticipantRights.none,
    WordAccess access = WordAccess.none,
  }) => _r.participant(
    who,
    vocabularies: vocabularies,
    rights: rights,
    access: access.or(_open),
  );

  /// An old name of a word (SPEC §6.4), as `Registry.alias`.
  IHandle alias(String old, String now) => _r.alias(old, now);

  /// A type of the host's (SPEC §2), as `Registry.registerType`.
  IHandle registerType(String name, String? Function(Object? value) check) =>
      _r.registerType(name, check);

  /// Ends it: every watch and stream ends.
  Future<void> dispose() => _r.dispose();
}
