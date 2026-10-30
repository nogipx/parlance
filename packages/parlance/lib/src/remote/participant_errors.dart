part of 'participant.dart';

/// The host cannot be asked now: the connection is down, or the session
/// ended. What the participant read before may be old.
final class HostUnreachable implements Exception {
  const HostUnreachable(this.why);
  final String why;

  @override
  String toString() => 'the registry cannot be reached now: $why';
}

/// What of the protocol the host speaks, as its `describe` told it (SPEC
/// §14): its features. Both ends must share the major, and the host must
/// speak each feature in [requires]; what else it speaks this end uses
/// when it knows it, and a feature it does not know it passes over.
/// Throws [ProtocolMismatch] otherwise.
Set<String> checkProtocol(
  Object? version, {
  Object? features,
  Set<String> requires = const {},
}) {
  if (version != parlanceProtocol) {
    throw ProtocolMismatch(host: version, here: parlanceProtocol);
  }
  final speaks = {for (final f in features as List? ?? const []) '$f'};
  final missing = requires.difference(speaks);
  if (missing.isNotEmpty) {
    throw ProtocolMismatch(
      host: version,
      here: parlanceProtocol,
      missing: missing,
    );
  }
  return speaks;
}

/// The host does not speak what this participant needs (SPEC §14): another
/// major of the protocol, or a feature it requires. Joining is refused,
/// rather than answers the other end does not understand.
final class ProtocolMismatch implements Exception {
  const ProtocolMismatch({
    required this.host,
    required this.here,
    this.missing = const {},
  });

  /// The host's major, as its `describe` told it (null: one too old to
  /// tell).
  final Object? host;
  final int here;

  /// The features this participant requires and the host does not speak;
  /// empty when the majors differ.
  final Set<String> missing;

  @override
  String toString() => missing.isEmpty
      ? 'the host speaks parlance protocol $host, this participant $here: '
            'build both against one parlance'
      : 'the host does not speak ${missing.join(', ')}, which this '
            'participant requires: a host built against a newer parlance does';
}

/// What a remote participant asked and the registry refused, told after:
/// over a connection the answer is not there when the participant asks
/// (SPEC §22.4).
final class ParticipantError {
  const ParticipantError(this.op, this.code, this.why);

  /// What it asked, as it was sent (`{op: define, descriptor: ...}`).
  final Map<String, Object?> op;

  /// What kind of no it is.
  final ParticipantErrorCode code;

  /// What happened, for people.
  final String why;

  @override
  String toString() => '${op['op']}: ${code.name}: $why';
}

/// What kind of no a [ParticipantError] tells, in the words a call's
/// refusal and a word's status use.
enum ParticipantErrorCode {
  /// It may not: a word outside its vocabularies, a right it lacks, a new
  /// session another's.
  notPermitted,

  /// What it defined is there already: a word, a guard, a kind.
  exists,

  /// What it sent is not what its word takes, or no op of the protocol.
  invalid,

  /// What it named is not there.
  missing,

  /// Past what its session lets it hold (`SessionLimits`), or what its
  /// listeners ask for past what a session carries by name.
  overLimit,

  /// The host could not do it now.
  unavailable,

  /// No answer came: the connection broke, or gave up.
  lost,

  /// Facts said while away were dropped, past those it keeps.
  dropped,

  /// The host it joins again speaks another protocol (SPEC §14).
  protocol,

  /// It read a value its code cannot read, built against the word
  /// otherwise (SPEC §25.2).
  unreadable,

  /// The host's feed brought what is no item of the protocol (`{op:
  /// feed}`), a host's defect: it follows again from a snapshot, or says
  /// it stopped.
  malformed,

  /// A word its code was built against is there otherwise (`{op: built,
  /// word}`), every break in [ParticipantError.why] (SPEC §6.9).
  mismatch,

  /// What a newer host says this side does not know.
  other;

  /// The code a session or this side says it by.
  static ParticipantErrorCode of(String code) => switch (code) {
    'permissionDenied' => notPermitted,
    'alreadyExists' => exists,
    'invalidArgument' => invalid,
    'notFound' => missing,
    'resourceExhausted' => overLimit,
    _ => values.asNameMap()[code] ?? other,
  };
}
