//! MTP — Miaotty Terminal Protocol.
//!
//! Wire types in [`types`](self) are generated from `proto/mtp.schema.json`
//! (see `proto/codegen.ts`). This crate adds the version constant and the
//! newline-delimited JSON codec used by every MTP peer.

mod types;

pub use types::*;

/// MTP protocol version implemented by this crate.
pub const PROTO_VERSION: i64 = 1;

/// Capabilities the miaotty host advertises in the scaffold.
pub const HOST_CAPS: &[Capability] = &[
    Capability::CoreBasic,
    Capability::AgentStateRead,
    Capability::AgentStateWrite,
];

/// Newline-delimited JSON codec (one MTP message per line).
pub mod line {
    use serde::de::DeserializeOwned;
    use serde::Serialize;

    /// Encode a message as JSON terminated by `\n`.
    pub fn encode<T: Serialize>(value: &T) -> String {
        let mut s = serde_json::to_string(value).expect("mtp: serialize");
        s.push('\n');
        s
    }

    /// Decode a single line (trailing newline tolerated).
    pub fn decode<T: DeserializeOwned>(line: &str) -> Result<T, serde_json::Error> {
        serde_json::from_str(line.trim_end())
    }
}
