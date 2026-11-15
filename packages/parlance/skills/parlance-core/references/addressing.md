# Exact target addresses

## Terminology

Use target for the exact whole principal to which a client binds. WordAddress.target
is that principal; WordAddress.word is the portable word name. WordTarget is one
discovered target with its principal and matching PublishedVocabulary groups; each
group has its name and PublishedWord entries. Discovery
uses targets and targetChanges. TargetDiscovery, generator arguments, runtime
helpers, MCP metadata and the mandatory targets protocol feature use this same
terminology. No alternate API names or compatibility aliases are provided.

This is an approved breaking migration. The former globally unique vocabulary
and unscoped generated clients are replaced, without a compatibility fallback.

- An address is `WordAddress(target, word)`, rendered as
  `kind[/id]/vocabulary.word`. The target is an exact whole principal;
  `Principal.whole` removes only `@owner`, preserving the instance id.
- `module`, `module/work` and `module/personal` are distinct publication
  identities and may publish the same vocabulary concurrently. ACL selectors
  retain their existing grouping semantics. Routing never uses `isWithin`.
- Each `(target, vocabulary)` has one live participant. Replacement of a
  session and disposal affect only its exact claims and resource handles.
- Portable words, shapes and schema entries do not contain a target.
  Runtime descriptors carry their full address in `name`. Fingerprints of
  contract entries remain independent of the deployment.
- Generated `<Class>Vocabulary` namespaces expose `name`, `words` and `definition`
  (`WordSet`). Names come from the annotation once; no former `<class>Words`
  constants remain. Generated clients require `target:`. `GeneratedWords(participant: participant,
  target: ...)` binds the caller and receiver separately; `.of(owner: owner,
  target: ...)` resolves the caller after attachment. `GeneratedWords.own(p)`
  is the generator's publication path. Definitions cannot claim another target.
- Reads, calls, subscriptions, snapshots, ticks, all three data stream kinds,
  statuses, schema diagnostics, aliases, usage, journal entries and causes carry
  the same full address. The wire uses its canonical string. Aliases stay inside
  one target. A repeated call id within a whole caller principal with a different
  receiver is an id conflict. Fact ids are scoped to their full publication address.
- `p.targets(vocabulary: HouseVocabulary.name)` and
  `p.targets(word: HouseCommand.setLight.name)` search by portable names and return
  actual publications grouped by principal, then vocabulary. Each
  `PublishedVocabulary` has `name` and `words`; each word retains its full address,
  portable descriptor, access and availability. Both filters intersect when given
  together. Discovery reports publication, not completeness or schema matching;
  typed clients check their own contract separately. Granted but unpublished
  vocabularies do not count. `targetChanges` observes these results and releases
  its listeners on cancellation. While disconnected, both snapshot and watch
  report no targets until the remote view synchronizes again. Discovery grants
  no access and selects no target.
- `OwnerTools.by` remains the caller, including after await and over RPC. The
  receiver is part of the operation address; `as` retains its caller-owner meaning.
- The `targets` protocol feature is mandatory for the new remote participant,
  including after reconnect. An unscoped request never chooses a target.
- TestHost stand-ins and observations require an explicit target too.
- Domain catalogs remain ordinary states or queries. Dynamic choices are gone;
  keyed values and enums remain. Owners validate entity IDs and remove keys.

The integration tests must cover all local/remote owner and consumer pairings,
coexisting bare and named principals, exact access and guards, data/call/fact/stream
isolation, schema/alias isolation, identity and causes, teardown and reconnect.
