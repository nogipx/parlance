# Changelog

## Unreleased

- Add atomic server/client/bidirectional stream words with typed input streams, native RPC streaming, half-close, cancellation and propagated flow control.

- Add `@ServerStreamWord`: typed owner factories and lazy clients, local and remote subscriptions, terminal errors, cancellation and configurable resource bounds.

## 0.1.1

- Support analyzer 9–14 and build 4/5 while retaining Dart 3.10 compatibility.

## 0.1.0

- First published release: the builder and source generator that make a
  vocabulary's typed words from an abstract class annotated with
  `@Vocabulary`.
