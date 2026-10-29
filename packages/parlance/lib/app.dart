/// What an app's `main` uses, a host's or a guest's, besides what its
/// words and owners do (`schema.dart`, exported here too): the [Host], the
/// rights of its participants, the sessions it serves its guests in, a
/// [Guest]'s join, and what they tell of errors.
///
/// It is frozen as `schema.dart` is (SPEC §14, §22, docs/план-api.md):
/// what it shows is never taken away, renamed or changed in meaning; it
/// only grows. What it shows is interfaces and final classes only the
/// library makes. The rest of the library (`registry.dart`,
/// `participant.dart`, `remote.dart`, `core.dart`) is there for tools and
/// tests, and promises less.
library;

export 'package:rpc_dart/logger.dart' show LogScope;

export 'schema.dart';
export 'src/host.dart' show Host, HostBounds, Guest;
export 'src/participant/participant.dart'
    show ParticipantRights, WordAccess, NotPermitted;
export 'src/remote/participant.dart'
    show IGuest, ParticipantError, ProtocolMismatch, RegistryUnreachable;
export 'src/remote/session.dart' show IGuestSession, SessionLimits;
