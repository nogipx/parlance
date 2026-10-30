/// What a developer of an app's words and owners works with, and what the
/// generated code names: the annotations, the words, their shapes and
/// types, the owner's tools, the participant as an interface and the one
/// door generated code reaches the words by ([GeneratedWords]), the
/// results of calls and statuses of words. Nothing else of the library:
/// a host's `main` imports `app.dart` besides, a tool `tools.dart`.
///
/// It is frozen (SPEC §23, docs/план-api.md): what it shows is never taken
/// away, renamed or changed in meaning; it only grows. A published words
/// package's `.g.dart` refers to nothing outside it.
///
/// The contract: skills/parlance/references/schema.md (§23).
library;

export 'src/core/core.dart' show IHandle;
export 'src/participant/owner.dart'
    show IOwner, OwnerTools, Choice, GuardCall, failCall, CallFailure;
export 'src/participant/participant.dart' show IParticipant, GeneratedWords;
export 'src/registry/cause.dart' show Principal;
export 'src/registry/ids.dart' show newId;
export 'src/registry/compat.dart' show WordBreak, BreakKind;
export 'src/registry/descriptors.dart' show Callers, Access;
export 'src/registry/messages.dart'
    show
        CallResult,
        CallDone,
        CallRefused,
        CallFailed,
        CallTimedOut,
        CallLost,
        Refusal,
        WordStatus,
        WordMissing,
        WordNotPermitted,
        WordUnavailable,
        WordReady,
        WordMismatch;
export 'src/registry/shapes.dart'
    show
        Shape,
        Plain,
        Nullable,
        ListShape,
        MapShape,
        RecordShape,
        Part,
        EnumShape,
        JsonShape,
        UnionShape,
        UnknownValue;
export 'src/registry/types.dart'
    show
        ValueType,
        BoolType,
        IntType,
        NumType,
        TextType,
        EnumType,
        DurationType,
        ChoiceType,
        ListType,
        ObjectType,
        Field,
        MapType,
        OneOfType,
        NullableType,
        CustomType,
        AnyType,
        UnknownType;
export 'src/registry/words.dart'
    show
        WordSet,
        IWord,
        IStateWord,
        ICommandWord,
        IQueryWord,
        IFactWord,
        Fact,
        IStateWriterOf,
        IFactEmitterOf,
        Keyed,
        Single,
        IStateOf,
        IKeyedOf,
        IFactOf,
        CallNotDone;
export 'src/schema/annotations.dart';
export 'src/schema/schema.dart';
