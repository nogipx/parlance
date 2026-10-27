/// Participants (SPEC §22): a part of the app sees the registry only as
/// one principal, defines words only in its namespaces, and is the same
/// whether the registry is in this process or across a connection.
///
/// The contract: skills/parlance/references/participant.md (§22).
library;

export 'src/participant/local.dart';
export 'src/participant/participant.dart';
