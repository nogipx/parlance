/// The library underneath, for tools: an agent's session, a journal, an
/// inspector, a host of plugins in another language, the package's own
/// tests. The registry and what it does by name and descriptor, the
/// participants as the library has them (`raw`), the session and the
/// participant across a connection, the view of a screen, and words named at
/// run time.
///
/// It is not frozen: it changes as the library does. An app's words,
/// owners and clients use `schema.dart`; its `main` uses `app.dart`.
///
/// The contract: skills/parlance/references/ (registry.md, participant.md,
/// remote.md, view.md).
library;

export 'src/host.dart' show HostRegistry;
export 'src/registry/cause.dart' show Principal, Cause, Origin;
export 'src/registry/compat.dart'
    show
        WordBreak,
        BreakKind,
        keepsPromises,
        entryBreaks,
        canonicalSchema,
        fingerprintOf;
export 'src/registry/descriptors.dart';
export 'src/registry/ids.dart'
    show newId, isValidName, isValidVocabularyName, checkWordName, wordVersion;
export 'src/registry/json.dart';
export 'src/registry/messages.dart'
    hide
        Kept,
        keptChange,
        keptValueOf,
        keptFact,
        keptPayloadOf,
        keptDone,
        keptAnswerOf,
        keptStarted,
        keptRecord;
export 'src/registry/registry.dart'
    hide Disposer, RawRegistry, paramsAs, answersAs, AnswerLost;
export 'src/registry/shapes.dart';
export 'src/registry/types.dart';
export 'src/registry/words.dart'
    hide factIn, StateWriterOf, FactSayerOf, CommandAnswers, QueryAnswers;
export 'src/participant/local.dart'
    hide
        Participants,
        registryOf,
        takeForServing,
        mayServe,
        EndSession,
        builtAgainstSchemas,
        forgetBuiltAgainst;
export 'src/participant/owner.dart' hide OwnerGroup;
export 'src/participant/participant.dart'
    hide defineCallOf, speakForCallOf, WordAccessOf;
export 'src/remote/participant.dart'
    show
        ParticipantError,
        ParticipantErrorCode,
        ProtocolMismatch,
        HostUnreachable,
        RemoteParticipant;
export 'src/remote/session.dart'
    show RemoteSession, ServeParticipant, SessionLimits;
export 'src/view/view.dart';
