# parlance_journal

**A registry's journal kept where it lasts: JSON lines, a file a day.**

[parlance](https://pub.dev/packages/parlance) keeps a record of who asked,
whether they were allowed, and why the world is as it is now. This package
reads that record back after the fact: as **conversations** (a call and
everything it led to, including how it ended), as **traces**, and as the
**links** between what happened and what it caused.

A journal is JSON lines, one file per day, written so an application stopped
at any moment loses at most the last few records. Lines written by a newer
build than the reader are skipped but reported, never silently mangled.

- The writer side (the registry's `JournalWriter`) lives in `package:parlance`;
  this package is the reader.
- Usage in code: the package's tests under `test/` read journals written the
  way a host writes them.
- Not frozen before `package:parlance` 1.0: what it shows may still change.
