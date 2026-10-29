/// What an app's `main` uses, a host's or a guest's, besides what its
/// words and owners do (`schema.dart`, exported here too): the registry,
/// its participants and their rights, the sessions it serves its guests
/// in, a guest's join, and a view for code that only reads and calls.
///
/// It is frozen as `schema.dart` is (SPEC §14, §22, docs/план-api.md):
/// what it shows is never taken away, renamed or changed in meaning; it
/// only grows. The rest of the library (`registry.dart`, `participant.dart`,
/// `remote.dart`, `core.dart`) is there for tools and tests, and promises
/// less.
library;

export 'package:rpc_dart/logger.dart' show LogScope;

export 'schema.dart';
export 'src/participant/local.dart' show Participants, LocalParticipant;
export 'src/participant/local_registry.dart' show LocalRegistry;
export 'src/participant/participant.dart'
    show ParticipantRights, WordAccess, NotPermitted;
export 'src/registry/messages.dart' show Mismatch, Explanation;
export 'src/registry/registry.dart' show Registry;
export 'src/remote/participant.dart'
    show
        RemoteParticipant,
        ParticipantError,
        ProtocolMismatch,
        RegistryUnreachable;
export 'src/remote/session.dart'
    show ServeParticipant, RemoteSession, SessionLimits;
export 'src/view/view.dart' show LocalView;
