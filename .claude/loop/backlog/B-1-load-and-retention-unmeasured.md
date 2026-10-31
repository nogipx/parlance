---
status: open
round: — (not re-measured)
commit: f68582b6f7473c9c3a5d2d0e570d0685932454d6
paths: [packages/parlance/lib/src/registry/**, packages/parlance/lib/src/remote/**, packages/parlance/benchmark/**]
probe: —
reason: bench — the area needs a load run and none exists; the prior audit measured it by reading only
rank: 1
---

# B-1 — load and long-livedness of a registry never measured by running

`docs/протечки.md` (pass 10, 2026-10-31) closes its leak audit with: «Не
пройдено: нагрузка и долгоживущесть (retention, рост памяти, лента под
множеством слушателей) — только чтением, не прогоном». What is unmeasured:
tick retention and eviction under a long run, memory growth with plugins
defining and removing words, the remote feed under many listeners, `keepAway`
(1000) facts held for away sessions, the compat judgement cache, call-record
retention. Harnesses exist but are not wired anywhere:
`packages/parlance/benchmark/memory_bench.dart`, `registry_bench.dart`,
`remote_bench.dart`, `realtime_bench.dart`, `big_doc_bench.dart`.

The claim to test is a bound, so the bench needs a control: e.g. a registry
that drops its eviction (ablation) must show the growth the production code
claims not to have. Links: lens PL-3.

## Owner decision

—
