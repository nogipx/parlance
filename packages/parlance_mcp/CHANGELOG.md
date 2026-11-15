# Changelog

## Unreleased

- Add provider discovery and full provider/word addresses in tool metadata and calls. Encode command tool names without punctuation or provider collisions.

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
