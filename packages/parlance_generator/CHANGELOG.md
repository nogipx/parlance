# Changelog

## Unreleased

- Breaking: generate fully named client factories (`participant:`, `target:`; `.of(owner:, target:)`) and bind owner publications to their own principal. Portable schemas remain independent of instances.

- Breaking: remove `@ChoiceOf` support and generated `<Class>Choices`
  constants. Keyed states retain `keyOf` as the key parameter name; string IDs
  use their ordinary text shape and are validated by the owner.

## 0.2.0

- Generate typed owners and clients for `@ServerStreamWord`, `@ClientStreamWord`
  and `@BidiStreamWord`, including typed input streams and cancellation.
- Require parlance 0.2.0 for the streaming annotations and generated runtime API.

## 0.1.1

- Support analyzer 9–14 and build 4/5 while retaining Dart 3.10 compatibility.

## 0.1.0

- First published release: the builder and source generator that make a
  vocabulary's typed words from an abstract class annotated with
  `@Vocabulary`.
