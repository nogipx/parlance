# Maintaining parlance

The release flow, the frozen surface, and the rpc_dart dependency. Modeled on
rpc_dart's MAINTAINING.md, leaner: no REUSE/SPDX headers, no shipped Agent
Skills, no packages outside the pub workspace.

## Layout

- `packages/parlance` — the core: `schema.dart` (words, shapes, types,
  participant) and `app.dart` (host, sessions, remote participant). The only
  frozen surface.
- `packages/parlance_generator` — the build_runner generator making typed
  words from `@Vocabulary` classes.
- `packages/parlance_journal`, `packages/parlance_links`,
  `packages/parlance_mcp` — the reader of a host's journal, reactions as
  data, and the MCP server (`parlance-mcp`).
- `apps/journal_viewer`, `examples/guests/*` — `publish_to: none`.

## Publishing

Every `packages/*` package is public; everything else is `publish_to: none`
and skipped by `melos publish` and `tag:release`.

Dependencies force the publish order: **parlance** first (everything depends
on it), then **parlance_generator**, then the rest in any order. `melos
publish` publishes everything unpublished in one run; for the first release
this is fine to run as-is, because pub.dev accepts an upload seconds before
its dependency lands. What you must not do is publish a dependent, wait, and
only then its dependency: between the two, the dependent's analysis on
pub.dev is broken.

## Release flow (every release, in order)

0. **`melos run prepare` — must be green.** Analyze (strict:
   `--fatal-infos --fatal-warnings`, so a public member without docs fails
   the gate), tests across the workspace, and the frozen-surface check.
0b. **The rpc_dart floor.** After a new rpc_dart release, every package that
   uses a new rpc_dart API needs its `rpc_dart:` floor raised — the pub
   workspace resolves rpc_dart from the hosted version, so a stale floor
   compiles and tests green here while a user on the old rpc_dart gets a
   compile error. Check with the overrides off (they must be off for a
   release anyway — see the root pubspec comment).
1. **Manual versioning.** Bump `version:` per changed package and write the
   CHANGELOG entry by hand (terse, why-focused). Do NOT use `melos version`.
   Do NOT tag here — `publish:release` tags.
2. Commit, push. The GitHub repo is the source of truth; `melos run
   publish:dry` wants a clean tree.
3. `melos run publish:dry` — validates every public package and previews the
   tags `publish:release` would create.
4. `fvm dart pub login`, then `melos run publish:release`. Publishes and
   then tags every public package at its pubspec version
   (`<pkg>-<version>`, e.g. `parlance-0.1.0`) and pushes. Publishing is
   irreversible — confirm versions first.
5. If it aborts partway, `melos run tag:release` finishes the tagging; do
   not re-run the publish (pub.dev rejects an existing version).

## The frozen surface

`tool/frozen.dart` (also `melos run frozen`) holds `packages/parlance`'s
`schema.dart` and `app.dart` to the last `parlance-<version>` tag: nothing
shown is taken away, renamed or changed; nothing is added to the interfaces
an app's code implements (`IOwner`, `IWord`, the word interfaces); and a
words package's `.g.dart` from then still builds with the library now. A
change that breaks it fails the release gate until the tag is moved by
releasing.

`tool/surface_map.dart` regenerates the surface map (`docs/surface-map.md`,
kept out of git, like the rest of `docs/`): the frozen
surface mapped to the tests that name each member. `none` and unexplained
`reached` rows are the "protruding but unverified" list; it is part of the
readiness work for 1.0, not yet a gate.

## Dependency on rpc_dart

rpc_dart is a separate repository (`../rpc_dart`), co-developed. It is
published; parlance resolves the published versions. The root pubspec
documents how to temporarily point the overrides at the local checkout for
co-development — and they must not be in place at release time, or the gates
test against rpc_dart the user does not have (the publish dry run only hints
at this; version solving against pub.dev is the real check, as a missing
`rpc_dart_socket 0.1.0` once showed).
