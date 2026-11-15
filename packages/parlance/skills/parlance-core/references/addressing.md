# Exact provider addresses

This is an approved breaking migration. The former globally unique vocabulary
and unscoped generated clients are replaced, without a compatibility fallback.

- An address is `WordAddress(provider, word)`, rendered as
  `kind[/id]/vocabulary.word`. The provider is an exact whole principal;
  `Principal.whole` removes only `@owner`, preserving the instance id.
- `module`, `module/work` and `module/personal` are distinct publication
  identities and may publish the same vocabulary concurrently. ACL selectors
  retain their existing grouping semantics. Routing never uses `isWithin`.
- Each `(provider, vocabulary)` has one live participant. Replacement of a
  session and disposal affect only its exact claims and resource handles.
- Portable words, shapes and schema entries do not contain a provider.
  Runtime descriptors carry their full address in `name`. Fingerprints of
  contract entries remain independent of the deployment.
- Generated clients require `provider:`. `GeneratedWords(participant: participant,
  provider: ...)` binds the caller and receiver separately; `.of(owner: owner,
  provider: ...)` resolves the caller after attachment. `GeneratedWords.own(p)`
  is the generator's publication path. Definitions cannot claim another provider.
- Reads, calls, subscriptions, snapshots, ticks, all three data stream kinds,
  statuses, schema diagnostics, aliases, usage, journal entries and causes carry
  the same full address. The wire uses its canonical string. Aliases stay inside
  one provider. A repeated call id within a whole caller principal with a different
  receiver is an id conflict. Fact ids are scoped to their full publication address.
- `p.providers(vocabulary: words)` and `p.providers(word: word)` return actual
  publications grouped by principal, with a portable descriptor and current
  access, availability and schema status per word. Granted but unpublished
  vocabularies do not count. `providerChanges` observes these results and releases
  its listeners on cancellation. While disconnected, both snapshot and watch
  report no providers until the remote view synchronizes again. Discovery grants
  no access and selects no target.
- `OwnerTools.by` remains the caller, including after await and over RPC. The
  receiver is part of the operation address; `as` retains its caller-owner meaning.
- The `providers` protocol feature is mandatory for the new remote participant,
  including after reconnect. An unscoped request never chooses a provider.
- TestHost stand-ins and observations require an explicit provider too.
- Domain catalogs remain ordinary states or queries. Dynamic choices are gone;
  keyed values and enums remain. Owners validate entity IDs and remove keys.

The integration tests must cover all local/remote owner and consumer pairings,
coexisting bare and named principals, exact access and guards, data/call/fact/stream
isolation, schema/alias isolation, identity and causes, teardown and reconnect.
