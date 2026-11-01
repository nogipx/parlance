# parlance_links

**Reactions written as data, run by the participant that owns them: when
something happens, if something holds, call commands.**

[parlance](https://pub.dev/packages/parlance) lets a part of an app say what
it has, what it can be asked and what happened to it. This package adds the
next thing a system usually grows by hand: couplings between those words,
expressed as data instead of code. A link says: *when* these states or facts
change, *if* these conditions hold, *call* these commands.

Because links are data, the participant that owns them can load them, watch
what they read, and run them the same way in a test as in production — and a
link that reads something its participant may not read does not run, it says
so.

- Usage in code: the package's tests under `test/` build a participant with
  links and watch them fire.
- Depends on `package:parlance`.
- Not frozen before `package:parlance` 1.0: what it shows may still change.
