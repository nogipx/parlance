---
round: — (not re-measured)
commit: f68582b6f7473c9c3a5d2d0e570d0685932454d6
paths: [packages/*/test/**]
scope: [parlance, parlance_generator, parlance_journal, parlance_links, parlance_mcp]
---

# C-2 — all five package test suites green at HEAD

Measured at setup by running each suite (concurrency as configured, loopback
sockets for the remote tests):

```
packages/parlance            569 passed  ~7 s
packages/parlance_generator   60 passed  ~6 s
packages/parlance_journal     21 passed  ~2 s
packages/parlance_links       21 passed  ~2 s
packages/parlance_mcp         40 passed ~11 s
```

Scope: this is a green-run snapshot, not a coverage claim — the where-matrix
(`test/contract/where_test.dart`) runs every scenario in all four
local/remote combinations, and the surface map (pass 10) found no member
outside tests. It exists so a round whose gate goes red can tell regression
from this baseline at a glance.

## Control

The suites demonstrably see defects: every pass-9 fix landed with a test that
failed before it (`b93a6f6`, `31b8262`, `4c26573`, `e1570da`, `2cb1b2f`),
and `fvm dart analyze` at HEAD is red (B-2) while the suites are green — the
two channels disagree exactly where each is sensitive.
