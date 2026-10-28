/// The registry: states, commands and facts that participants share
/// without knowing each other, guards and the feed.
///
/// The contract: skills/parlance/references/registry.md (§1–12).
library;

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
    show newId, isValidName, checkWordName, wordVersion;
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
export 'src/registry/registry.dart' hide RawRegistry, paramsAs, answersAs;
export 'src/registry/shapes.dart';
export 'src/registry/types.dart';
export 'src/registry/words.dart'
    hide TypedRegistry, StateOf, CommandOf, QueryOf, FactOf;
