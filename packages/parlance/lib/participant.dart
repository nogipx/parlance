/// Participants (SPEC §22): a part of the app sees the registry only as
/// one principal, defines words only in its vocabularies, is
/// the same whether the registry is in this process or across a
/// connection, and holds the owners `main` attaches to it: an [IOwner]
/// defines its words, keeps their handles and writes its states; a
/// [TrackedKind] tells the registry when a kind's entities changed.
///
/// The contract: skills/parlance/references/participant.md (§22) and
/// owners.md (§19).
library;

export 'src/participant/local.dart'
    hide
        registryOf,
        takeForServing,
        builtAgainstSchemas,
        forgetBuiltAgainst;
export 'src/participant/owner.dart' hide OwnerGroup;
export 'src/participant/participant.dart';
