---
round: — (not re-measured)
commit: f68582b6f7473c9c3a5d2d0e570d0685932454d6
paths: [packages/parlance/lib/**, packages/parlance_links/lib/**, packages/parlance_mcp/lib/**, packages/parlance_journal/lib/**, packages/parlance_generator/lib/**]
scope: [parlance, parlance_links, parlance_mcp, parlance_journal, parlance_generator]
---

# C-1 — the prior leak audit's findings stay closed at HEAD

Ten audit passes (`docs/протечки.md`, passes 1-10, 2026-10-31) produced 16
frozen-boundary leaks plus journal leaks J1-J4 and pass-9 findings Н1-Н12; all
are recorded closed, each with a regression test named in the doc and visible
in the git history of HEAD (e.g. `2cb1b2f`, `673cda2`, `7b3014d`). The pass-10
sweep of the hub, feed, retention and the edges of shapes/types found no new
leaks; the surface map reported 0 members outside tests (`6603c25`).

This record only carries the closures forward so the loop does not re-open
them from the doc's word. What it does NOT cover: the load/long-livedness
area the same doc names as unmeasured — that is backlog B-1, not a negative.

## Control

Each closure names a test that fails on the pre-fix code, checked into
history one commit before its fix (doc: «После исправления — тест, который
падает на старом коде и проходит на новом»). The bench could see the defect
class: it did, twelve times in pass 9 alone.
