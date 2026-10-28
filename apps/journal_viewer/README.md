# journal_viewer

Conversations of a parlance journal (`parlance_journal`'s JSON lines),
loaded, drawn and played back. Runs in a browser and on macOS.

- **Open or drop** journal files (`journal-2026-10-28.jsonl`; several days at
  once go in the order of their days). In a browser, `?journal=<url>` opens
  the journal at that address, relative to the viewer's: a link to a journal
  opens it.
- **Conversations**: when each started, the word it started with and who
  (its origin), how long it went on, how many entries, and its calls
  refused, failed or timed out. Search by word, who or id; *Problems* keeps
  those with a refusal, a failure or a timeout.
- **A conversation** as a tree on its time: each message under the one it
  followed from, a call as a bar from its start to its end, a fact and a
  write as a mark; colours tell how a call ended.
- **A message**: who, when, what it follows from, its conversation and
  origin, its trace, how a call ended and why, its values, how it came about
  (the path from the first message), and the entry as written.
- **Playback**: the playhead goes over what was loaded at 1×, 10×, 60× or
  600×, jumping quiet stretches; the list and the tree show only what had
  happened by then. Stop shows everything again.

```sh
fvm flutter run -d chrome            # or -d macos
fvm flutter build web --no-web-resources-cdn   # self-contained, to serve anywhere
fvm dart run tool/sample_journal.dart          # a sample journal to look at
```
