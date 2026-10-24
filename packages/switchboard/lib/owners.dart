/// Owners: what every host that puts words in a registry needs, curated.
/// An [Owner] defines its words, keeps their handles and writes its states;
/// [Owners] attaches several to one registry and syncs them as one tick;
/// [Handles] withdraws what was put in, the last first; a [TrackedKind]
/// tells the registry when a kind's entities changed.
///
/// The contract: skills/switchboard/references/owners.md (§19).
library;

export 'src/owners/owners.dart';
