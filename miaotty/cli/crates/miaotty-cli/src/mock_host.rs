//! A standalone dev host implementing the MTP `core` + `agent.state` methods.
//!
//! It exists so the integration spine is verifiable without the macOS app:
//! `miaotty-cli mock-host` + `miaotty-cli ping|state …`.

use std::collections::BTreeMap;
use std::fs;
use std::io::{BufRead, BufReader, Write};
use std::os::unix::fs::PermissionsExt;
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::Path;

use anyhow::{Context, Result};
use mtp::{
    AgentStateInfo, AgentStateListResult, AgentStateSetParams, ErrorInfo, HealthResult, PingResult,
    Request, Response, WelcomeParams,
};

#[derive(Default)]
struct Registry {
    revision: i64,
    seq: i64,
    states: BTreeMap<String, AgentStateInfo>,
}

impl Registry {
    fn key(p: &AgentStateSetParams) -> String {
        if let Some(pane) = &p.pane_id {
            return format!("pane:{pane}");
        }
        if let Some(tty) = &p.tty {
            return format!("tty:{tty}");
        }
        format!(
            "sess:{}:{}",
            p.agent,
            p.session_id.as_deref().unwrap_or("-")
        )
    }

    fn set(&mut self, p: AgentStateSetParams) -> i64 {
        let key = Self::key(&p);
        self.revision += 1;
        self.seq += 1;
        let info = AgentStateInfo {
            agent: p.agent,
            session_id: p.session_id,
            pane_id: p.pane_id,
            state: p.state,
            cwd: p.cwd,
            bypass: p.bypass,
            error_kind: p.error_kind,
            title: p.title,
            ts: p.ts,
            seq: Some(self.seq),
        };
        self.states.insert(key, info);
        self.revision
    }
}

fn ok(id: i64, revision: i64, result: serde_json::Value) -> Response {
    Response {
        v: mtp::PROTO_VERSION,
        id,
        kind: "res".to_string(),
        ok: true,
        result: Some(result),
        error: None,
        revision: Some(revision),
    }
}

fn err(id: i64, revision: i64, code: &str, message: &str, retryable: bool) -> Response {
    Response {
        v: mtp::PROTO_VERSION,
        id,
        kind: "res".to_string(),
        ok: false,
        result: None,
        error: Some(ErrorInfo {
            code: code.to_string(),
            message: message.to_string(),
            retryable,
            details: None,
        }),
        revision: Some(revision),
    }
}

fn dispatch(reg: &mut Registry, req: Request) -> Response {
    let id = req.id;
    let params = req.params.clone().unwrap_or(serde_json::Value::Null);
    match (req.ns.as_str(), req.method.as_str()) {
        ("core", "ping") => {
            let result = serde_json::to_value(PingResult {
                proto: mtp::PROTO_VERSION,
                app_version: format!("mock-host/{}", env!("CARGO_PKG_VERSION")),
                pid: std::process::id() as i64,
                caps: mtp::HOST_CAPS.to_vec(),
            })
            .unwrap();
            ok(id, reg.revision, result)
        }
        ("core", "health") => {
            let result = serde_json::to_value(HealthResult {
                ok: true,
                revision: reg.revision,
                connections: Some(1),
                events_per_sec: Some(0.0),
                dropped_events: Some(0),
            })
            .unwrap();
            ok(id, reg.revision, result)
        }
        ("core", "hello") => {
            let result = serde_json::to_value(WelcomeParams {
                proto: mtp::PROTO_VERSION,
                session: "mock".to_string(),
                caps: mtp::HOST_CAPS.to_vec(),
                limits: mtp::Limits {
                    max_message_bytes: 1 << 20,
                    rate_per_sec: 500,
                    idle_timeout_ms: 300_000,
                },
                revision: reg.revision,
            })
            .unwrap();
            ok(id, reg.revision, result)
        }
        ("agent", "state.set") => match serde_json::from_value::<AgentStateSetParams>(params) {
            Ok(p) => {
                let revision = reg.set(p);
                ok(id, revision, serde_json::json!({ "revision": revision }))
            }
            Err(e) => err(id, reg.revision, "bad_request", &e.to_string(), false),
        },
        ("agent", "state.list") => {
            let result = serde_json::to_value(AgentStateListResult {
                revision: reg.revision,
                states: reg.states.values().cloned().collect(),
            })
            .unwrap();
            ok(id, reg.revision, result)
        }
        ("pane", "list") => ok(id, reg.revision, serde_json::json!({ "panes": [] })),
        _ => err(
            id,
            reg.revision,
            "bad_request",
            &format!("unknown method {}.{}", req.ns, req.method),
            false,
        ),
    }
}

fn handle_conn(mut stream: UnixStream, reg: &mut Registry) -> Result<()> {
    let peer = stream.try_clone()?;
    let mut reader = BufReader::new(peer);
    loop {
        let mut buf = String::new();
        let n = reader.read_line(&mut buf)?;
        if n == 0 {
            return Ok(());
        }
        let req: Request = match mtp::line::decode(&buf) {
            Ok(r) => r,
            Err(e) => {
                let resp = err(0, reg.revision, "bad_request", &e.to_string(), false);
                stream.write_all(mtp::line::encode(&resp).as_bytes())?;
                stream.flush()?;
                continue;
            }
        };
        let resp = dispatch(reg, req);
        stream.write_all(mtp::line::encode(&resp).as_bytes())?;
        stream.flush()?;
    }
}

/// Bind `path` and serve until the process is terminated.
pub fn run(path: &Path) -> Result<()> {
    if path.exists() {
        fs::remove_file(path).ok();
    }
    if let Some(dir) = path.parent() {
        fs::create_dir_all(dir).ok();
    }

    let listener = UnixListener::bind(path).with_context(|| format!("bind {}", path.display()))?;
    fs::set_permissions(path, fs::Permissions::from_mode(0o600)).ok();

    println!("miao-mock-host listening on {}", path.display());
    println!("  export MIAOTTY_SOCKET={}", path.display());

    let mut reg = Registry::default();
    for stream in listener.incoming() {
        match stream {
            Ok(s) => {
                if let Err(e) = handle_conn(s, &mut reg) {
                    eprintln!("connection error: {e}");
                }
            }
            Err(e) => eprintln!("accept error: {e}"),
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::client::Client;
    use std::time::Duration;

    #[test]
    fn ping_and_state_roundtrip() {
        let path = std::env::temp_dir().join(format!("miaotty-test-{}.sock", std::process::id()));
        let p = path.clone();
        std::thread::spawn(move || {
            let _ = run(&p);
        });
        // wait for the listener
        for _ in 0..50 {
            if path.exists() {
                break;
            }
            std::thread::sleep(Duration::from_millis(20));
        }

        let mut c = Client::connect(&path, Duration::from_secs(3)).expect("connect");
        let ping = c.call("core", "ping", serde_json::json!({})).expect("ping");
        assert!(ping.ok);
        assert_eq!(ping.result.unwrap()["proto"], 1);

        let set = c
            .call(
                "agent",
                "state.set",
                serde_json::json!({"agent":"miao","state":"processing","pane_id":"pane_1"}),
            )
            .expect("state.set");
        assert!(set.ok);
        assert_eq!(set.revision, Some(1));

        let list = c
            .call("agent", "state.list", serde_json::json!({}))
            .expect("state.list");
        let result = list.result.unwrap();
        assert_eq!(result["states"].as_array().unwrap().len(), 1);
        assert_eq!(result["states"][0]["state"], "processing");

        std::fs::remove_file(&path).ok();
    }
}
