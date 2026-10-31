---
status: closed (round 1)
round: 1
commit: f68582b6f7473c9c3a5d2d0e570d0685932454d6
paths: [packages/parlance/test/remote/newer_language_test.dart, packages/parlance/test/registry/calls_test.dart]
probe: —
reason: risk — the gate is red from day one; every later round's gate output has to be eyeballed against these two known lines
rank: 2
---

# B-2 — gate red at HEAD: two import lints in parlance tests

Measured at setup (this session, HEAD f68582b):

```text
warning - packages/parlance/test/remote/newer_language_test.dart:4:8 - Unused import: 'package:parlance/src/remote/client.dart'
info    - packages/parlance/test/registry/calls_test.dart:5:8 - Unnecessary import: 'package:parlance/schema.dart' (elements also provided by tools.dart)
fvm dart analyze exit code: 2
```

Mechanism: nothing subtle — dead imports in two test files. Cost of leaving:
every round's gate step reports these two lines and must distinguish them
from its own regressions; the first round touching either file should remove
the import and close this lead. The fix itself is below the severity bar; it
is here so the gate goes green, not because it is a defect worth a hunt.

Closed by round 1: both imports removed, `fvm dart analyze` exit 2 -> 0
("No issues found!"), canary re-adding the imports reproduced both
diagnostics, parlance suite 569 passed.

## Owner decision

—
