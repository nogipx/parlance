/// What an app's `main` uses, in the host's process or in another that
/// joins it, besides what its words and owners do (`schema.dart`, exported
/// here too): the [Host], the rights of its participants, the sessions it
/// serves across a connection ([Host.serve]), the join from the other end
/// ([Host.join]), and what they tell of errors.
///
/// It follows `schema.dart`'s version policy (SPEC §14, §22): a minor release
/// before 1.0, or a major release from 1.0, may change the API incompatibly.
/// Within that line it stays source compatible. It shows interfaces and final
/// classes only the library makes. The rest of the library (`tools.dart`) is there for
/// tools and the package's tests, and promises nothing.
library;

export 'package:rpc_dart/logger.dart' show LogScope;

export 'schema.dart';
export 'src/host.dart' show Host;
export 'src/registry/registry.dart' show HostLimits;
export 'src/participant/participant.dart'
    show
        ParticipantRights,
        DefineCall,
        SpeakForCall,
        WordRole,
        WordAccess,
        NotPermitted;
export 'src/remote/participant.dart'
    show
        IRemoteParticipant,
        ParticipantError,
        ParticipantErrorCode,
        ProtocolMismatch,
        HostUnreachable;
export 'src/remote/session.dart' show IRemoteSession, SessionLimits;

export 'src/registry/streams.dart' show StreamLimits;
