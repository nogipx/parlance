/// The registry over rpc_dart (SPEC §14): the host serves a participant
/// across a connection (`participant.serve(endpoint)`, a [RemoteSession]),
/// and the part at the other end is a participant there too
/// ([RemoteParticipant]), the same `IParticipant` as in the host's
/// process. The wire, its client and the mirror are the package's.
library;

export 'src/remote/participant.dart'
    show
        ParticipantError,
        ProtocolMismatch,
        RegistryUnreachable,
        RemoteParticipant;
export 'src/remote/session.dart' show RemoteSession, ServeParticipant;
