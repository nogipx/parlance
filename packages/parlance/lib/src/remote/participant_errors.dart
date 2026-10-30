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

  /// The session's status: `permissionDenied`, `alreadyExists`,
  /// `invalidArgument`, `notFound`; `lost` when the answer did not come;
  /// `unreadable` when it read a value its code cannot read, built against
  /// the word otherwise (SPEC §25.2); `malformed` when the host's feed
  /// brought what is no item of the protocol (`{op: feed}`), a host's
  /// defect: it follows again from a snapshot, or says it stopped;
  /// `mismatch` when a word its code was built against is there otherwise
  /// (`{op: built, word}`), every break in the message (SPEC §6.9).
  final String code;
  final String why;

  @override
  String toString() => '${op['op']}: $code: $why';
}
