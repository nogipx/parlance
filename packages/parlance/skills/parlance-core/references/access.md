# Host access policy and unexpected-dependency diagnostics

Approved implementation contract. Host.setAccess(address:, access:) installs an
immutable field-wise override for an exact WordAddress. Host.clearAccess restores
the declared policy. Precedence: host field override, annotation, participant
default, existing implicit access. Selector maps replace as a whole. Null inherits;
an empty Callers denies everyone. Commands, queries and input streams use callers;
states, facts and server streams use readers. Only the host mutates policies.
Overrides may precede publication, survive re-publication/reconnect of the same
provider, and end with their host or explicit clearing. Aliases use the target.

Declarations and owner handles remain unchanged. Effective descriptors, statuses,
discovery, MCP and RPC catalogs all reflect host policy. ACL changes are catalog
changes, not schema changes. New requests and retries check current ACL. Successful
retry identity is retained even while denied. Admission is rechecked after awaits
before a handler starts; started calls finish normally.

State/fact subscriptions retain their desired words while access is denied, stop
delivery, and resume when granted. States refresh from current values; facts do not
replay. Revoked state values are removed from remote mirrors. Queued undelivered
items are checked again. Per-address accessRevisions travel with the catalog so
queued state snapshots and facts can be rejected even after a rapid revoke/regrant.
Normal initial values and updates retain their delivery semantics. Active data streams close with notPermitted when revoked.

Access.warn permits an interaction and records an AccessWarning with caller, word,
operation, time, optional ID and cause. Commands/queries warn on invocation, streams
on opening, states/facts on actual reads or subscription admission. Status/catalog/
discovery are silent; delivered elements do not warn individually. Host tools can
observe registry.accessWarnings; LogScope records warnings, with development-only
diagnostics when no logger is configured. Arguments and payloads are not recorded.
