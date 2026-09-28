mod client;
mod mock_host;

use std::path::PathBuf;
use std::time::Duration;

use anyhow::{bail, Result};
use clap::{Parser, Subcommand};
use mtp::{AgentState, AgentStateSetParams};

#[derive(Parser)]
#[command(
    name = "miaotty-cli",
    version,
    about = "Control CLI for the miaotty terminal (MTP over a Unix socket)."
)]
struct Cli {
    /// Host socket path (default: $MIAOTTY_SOCKET or $TMPDIR/miaotty.sock).
    #[arg(long, global = true)]
    socket: Option<PathBuf>,

    /// Request timeout in milliseconds.
    #[arg(long, global = true, default_value_t = 3000)]
    timeout: u64,

    #[command(subcommand)]
    cmd: Cmd,
}

#[derive(Subcommand)]
#[allow(clippy::large_enum_variant)]
enum Cmd {
    /// Check that a host is reachable.
    Ping,
    /// Host health/registry revision.
    Health,
    /// Agent state plane.
    State {
        #[command(subcommand)]
        sub: StateCmd,
    },
    /// Terminal topology.
    Pane {
        #[command(subcommand)]
        sub: PaneCmd,
    },
    /// Per-pane command history (details "Outline" panel).
    History {
        #[command(subcommand)]
        sub: HistoryCmd,
    },
    /// Run a standalone dev host (no macOS app required).
    MockHost,
}

#[derive(Subcommand)]
enum HistoryCmd {
    /// Record a command executed in a pane (called by the shell hook).
    Add(HistoryAddArgs),
    /// List recorded commands.
    List(HistoryListArgs),
}

#[derive(clap::Args)]
struct HistoryAddArgs {
    #[arg(long)]
    command: String,
    #[arg(long)]
    cwd: Option<String>,
    #[arg(long)]
    pane: Option<String>,
    #[arg(long)]
    tty: Option<String>,
    #[arg(long = "exit-code")]
    exit_code: Option<i64>,
}

#[derive(clap::Args)]
struct HistoryListArgs {
    #[arg(long)]
    pane: Option<String>,
    #[arg(long)]
    tty: Option<String>,
    #[arg(long)]
    limit: Option<i64>,
}

#[derive(Subcommand)]
enum PaneCmd {
    /// List panes known to the host.
    List,
}

#[derive(Subcommand)]
#[allow(clippy::large_enum_variant)]
enum StateCmd {
    /// Report agent state for a pane/session.
    Set(StateSetArgs),
    /// List all known agent states.
    List,
}

#[derive(clap::Args)]
struct StateSetArgs {
    #[arg(long)]
    agent: String,
    /// processing | idle | awaiting | error
    #[arg(long)]
    state: String,
    #[arg(long)]
    pane: Option<String>,
    #[arg(long)]
    session: Option<String>,
    #[arg(long)]
    tty: Option<String>,
    #[arg(long = "agent-pid")]
    agent_pid: Option<i64>,
    #[arg(long)]
    cwd: Option<String>,
    #[arg(long)]
    bypass: bool,
    #[arg(long = "error-kind")]
    error_kind: Option<String>,
    #[arg(long)]
    title: Option<String>,
}

fn parse_state(s: &str) -> Result<AgentState> {
    Ok(match s {
        "processing" => AgentState::Processing,
        "idle" => AgentState::Idle,
        "awaiting" => AgentState::Awaiting,
        "error" => AgentState::Error,
        other => bail!("invalid --state {other:?} (processing|idle|awaiting|error)"),
    })
}

/// Rewrite the shell-integration form `state:<agent> <args…>` into
/// `state set --agent <agent> <args…>` before clap parses argv.
fn normalize_argv(argv: Vec<String>) -> Vec<String> {
    // Shell-integration shorthand `state:<agent> …` -> `state set --agent <agent> …`
    if let Some(i) = argv
        .iter()
        .position(|a| a.starts_with("state:") && a.len() > "state:".len())
    {
        let agent = argv[i]["state:".len()..].to_string();
        let mut out = argv[..i].to_vec();
        out.push("state".to_string());
        out.push("set".to_string());
        out.push("--agent".to_string());
        out.push(agent);
        out.extend_from_slice(&argv[i + 1..]);
        return out;
    }

    // Shell-integration shorthand `history:add …` -> `history add …`
    if let Some(i) = argv.iter().position(|a| a == "history:add") {
        let mut out = argv[..i].to_vec();
        out.push("history".to_string());
        out.push("add".to_string());
        out.extend_from_slice(&argv[i + 1..]);
        return out;
    }

    argv
}

fn main() -> Result<()> {
    let argv = normalize_argv(std::env::args().collect());
    let cli = Cli::parse_from(argv);
    let socket = cli.socket.clone().unwrap_or_else(client::default_socket);

    if let Cmd::MockHost = cli.cmd {
        return mock_host::run(&socket);
    }

    let deadline = Duration::from_millis(cli.timeout);
    let mut c = client::Client::connect(&socket, deadline)?;

    let resp = match cli.cmd {
        Cmd::Ping => c.call("core", "ping", serde_json::json!({}))?,
        Cmd::Health => c.call("core", "health", serde_json::json!({}))?,
        Cmd::State {
            sub: StateCmd::List,
        } => c.call("agent", "state.list", serde_json::json!({}))?,
        Cmd::State {
            sub: StateCmd::Set(args),
        } => {
            let params = AgentStateSetParams {
                agent: args.agent,
                session_id: args.session,
                // Default to the pane we run in, so hooks need no arguments.
                pane_id: args.pane.or_else(|| std::env::var("MIAOTTY_PANE_ID").ok()),
                tty: args.tty,
                agent_pid: args.agent_pid,
                state: parse_state(&args.state)?,
                cwd: args.cwd,
                bypass: if args.bypass { Some(true) } else { None },
                error_kind: args.error_kind,
                title: args.title,
                ts: None,
            };
            c.call("agent", "state.set", serde_json::to_value(params)?)?
        }
        Cmd::Pane { sub: PaneCmd::List } => c.call("pane", "list", serde_json::json!({}))?,
        Cmd::History {
            sub: HistoryCmd::Add(a),
        } => {
            let params = serde_json::json!({
                "command": a.command,
                "cwd": a.cwd,
                "pane_id": a.pane.or_else(|| std::env::var("MIAOTTY_PANE_ID").ok()),
                "tty": a.tty,
                "exit_code": a.exit_code,
            });
            c.call("history", "add", params)?
        }
        Cmd::History {
            sub: HistoryCmd::List(a),
        } => {
            let params = serde_json::json!({
                "pane_id": a.pane.or_else(|| std::env::var("MIAOTTY_PANE_ID").ok()),
                "tty": a.tty,
                "limit": a.limit,
            });
            c.call("history", "list", params)?
        }
        Cmd::MockHost => unreachable!(),
    };

    if !resp.ok {
        let e = resp.error.expect("error response without error payload");
        eprintln!("error [{}] {}", e.code, e.message);
        std::process::exit(1);
    }
    println!(
        "{}",
        serde_json::to_string_pretty(&resp.result.unwrap_or(serde_json::Value::Null))?
    );
    Ok(())
}
