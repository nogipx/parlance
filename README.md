# parlance

A language the parts of an app speak to each other in: states, commands,
queries and facts, who may say what, why each thing happened, and a journal
of it all.

| Package | What it is |
|---|---|
| `packages/parlance` | The language: the registry, participants and owners, remote, MCP. Its contract is `packages/parlance/skills/parlance`. |
| `packages/parlance_generator` | Typed words from a vocabulary written once. |
| `packages/parlance_links` | Reactions written as data, run by the participant that owns them. |
| `packages/parlance_journal` | The journal kept where it lasts, and read back. |

| `apps/journal_viewer` | Conversations of a journal, loaded, drawn as trees on their time and played back; web and macOS. |
| `examples/guests` | A host and two widlet guests: each guest a participant of the host's registry, one using the other's words and the host's, typed, through their words packages. |

`docs/термины.md` is the glossary in Russian.

Run `fvm dart pub get` here, then `fvm dart test` in a package.
