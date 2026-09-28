//! Minimal MTP client: connect to the host socket, issue one request, read
//! the matching response. Events pushed by the host are skipped.

use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::UnixStream;
use std::path::{Path, PathBuf};
use std::time::Duration;

use anyhow::{anyhow, Context, Result};
use mtp::{line, Request, Response};

/// Resolve the host socket path: `$MIAOTTY_SOCKET`, else `$TMPDIR/miaotty.sock`.
pub fn default_socket() -> PathBuf {
    if let Ok(p) = std::env::var("MIAOTTY_SOCKET") {
        return PathBuf::from(p);
    }
    let tmp = std::env::var("TMPDIR").unwrap_or_else(|_| "/tmp/".to_string());
    PathBuf::from(tmp).join("miaotty.sock")
}

pub struct Client {
    reader: BufReader<UnixStream>,
    writer: UnixStream,
    next_id: i64,
}

impl Client {
    pub fn connect(path: &Path, timeout: Duration) -> Result<Self> {
        let stream =
            UnixStream::connect(path).with_context(|| format!("connect {}", path.display()))?;
        stream.set_read_timeout(Some(timeout))?;
        stream.set_write_timeout(Some(timeout))?;
        let writer = stream.try_clone()?;
        Ok(Self {
            reader: BufReader::new(stream),
            writer,
            next_id: 0,
        })
    }

    pub fn call(&mut self, ns: &str, method: &str, params: serde_json::Value) -> Result<Response> {
        self.next_id += 1;
        let id = self.next_id;
        let req = Request {
            v: mtp::PROTO_VERSION,
            id,
            kind: "req".to_string(),
            ns: ns.to_string(),
            method: method.to_string(),
            params: Some(params),
            role: Some(mtp::Role::Client),
            caps: None,
            ts: Some(now_ms()),
            trace: None,
        };
        self.writer.write_all(line::encode(&req).as_bytes())?;
        self.writer.flush()?;

        loop {
            let mut buf = String::new();
            let n = self.reader.read_line(&mut buf)?;
            if n == 0 {
                return Err(anyhow!("host closed the connection"));
            }
            let value: serde_json::Value = line::decode(&buf)?;
            if value.get("kind").and_then(|k| k.as_str()) == Some("evt") {
                continue; // ignore pushed events in the one-shot client
            }
            let res: Response = serde_json::from_value(value)?;
            if res.id == id {
                return Ok(res);
            }
        }
    }
}

fn now_ms() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}
