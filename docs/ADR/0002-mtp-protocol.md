# ADR 0002 — MTP: one contract, many transports

## Context

miao and miaotty must feel like one product, but their implementations will
change independently (today: a plugin + CLI + socket; later possibly in-process
embedding or remote). Hard-coding any one integration mechanism couples the two
release cycles and risks version skew.

## Decision

Define **MTP (Miaotty Terminal Protocol)** as the stable contract, with a single
JSON-Schema source (`miaotty/proto/mtp.schema.json`) and codegen for Rust,
Swift and TypeScript.

- One connection, one envelope (`req`/`res`/`evt`), four planes: **state,
  context, control, UI**.
- Versioned (`v`) with a capability handshake (`hello`/`welcome`); new fields are
  optional and unknown capabilities/fields are ignored.
- Transport is abstracted (Unix socket primary; stdio and in-process later).
- State is idempotent and last-write-wins per key `(pane, session)`, with a
  monotonic `seq` and a `revision` for reconciliation.

## Consequences

- Implementations can be swapped without a protocol change. The scaffold proves
  it: a Swift host and a Rust CLI already interoperate over MTP.
- Codegen drift is a CI failure; the schema is the only place types are edited.
- Peers must handle version skew and degrade gracefully (terminal never depends
  on the agent).

## Alternatives considered

- **Ad-hoc CLI only** — simple, but no bidirectional/UI plane and no clean path to
  in-process integration. Kept as the zero-install fallback level.
- **Embedding miao directly** — not precluded (in-process transport), but not the
  contract.
