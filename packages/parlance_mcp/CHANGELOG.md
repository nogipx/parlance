# Changelog

## 0.2.0

- Extend `why` with call inspection and bounded state history, mixed causal messages and explicit evidence gaps.
- Return caller IDs in `structuredContent.call`, including automatically generated IDs, for later inspection.

- Require parlance 0.3.0.

- Breaking: group targets tool publications by vocabulary and use the shared name-based discovery filters.

- Require rpc_dart 7.2.0.

- Reflect live host access policy in command discovery, state reads and calls; preserve warn metadata while the host records actual accesses.

- Add target discovery and full target/word addresses in tool metadata and calls. Encode command tool names without punctuation or target collisions.

- Breaking: remove the entity directory from `describe` and dynamic choices
  from JSON Schema generation. Domain catalogs use ordinary states or queries;
  static enums continue to expose their values.

## 0.1.2

- Support parlance 0.2.0 and its generator.

## 0.1.1

- Fix the link to the packaged parlance-core contract documentation.

## 0.1.0

- First published release: the `parlance-mcp` server speaking a host's
  parlance to agents over stdio, over a Unix socket or TCP.
