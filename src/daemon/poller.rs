use std::collections::{HashMap, HashSet};
use std::sync::Arc;

use tokio::process::Command;
use tokio::sync::{Mutex, broadcast};
use tokio::time::{Duration, interval};

use crate::protocol::ServerMessage;

use super::state::SessionMap;

/// Run a single poll: discover claude processes, register new sessions, remove stale ones.
pub async fn poll_once(state: &Arc<Mutex<SessionMap>>, tx: &broadcast::Sender<ServerMessage>) {
    let Some(panes) = list_tmux_panes().await else {
        return;
    };

    let pane_by_pid: HashMap<u32, (&str, &str)> = panes
        .iter()
        .map(|p| (p.pane_pid, (p.pane_id.as_str(), p.cwd.as_str())))
        .collect();

    let claude_panes = find_claude_panes(&pane_by_pid).await;

    let mut map = state.lock().await;
    let known_panes = map.pane_session_map();

    let active_pane_ids: HashSet<&str> =
        claude_panes.iter().map(|c| c.pane_id.as_str()).collect();

    for cp in &claude_panes {
        if known_panes.contains_key(&cp.pane_id) {
            continue;
        }
        let session_id = format!("polled-{}", cp.pane_id.trim_start_matches('%'));
        if let Some(msg) = map.register_polled(session_id, cp.cwd.clone(), cp.pane_id.clone()) {
            let _ = tx.send(msg);
        }
    }

    let to_remove: Vec<String> = known_panes
        .iter()
        .filter(|(pane_id, session_id)| {
            session_id.starts_with("polled-") && !active_pane_ids.contains(pane_id.as_str())
        })
        .map(|(_, session_id)| session_id.clone())
        .collect();

    for session_id in to_remove {
        if let Some(msg) = map.remove(&session_id) {
            let _ = tx.send(msg);
        }
    }
}

/// Periodically scan for Claude Code processes and match them to tmux panes.
pub async fn poll_loop(state: Arc<Mutex<SessionMap>>, tx: broadcast::Sender<ServerMessage>) {
    let mut ticker = interval(Duration::from_secs(5));

    loop {
        ticker.tick().await;
        poll_once(&state, &tx).await;
    }
}

struct ClaudePane {
    pane_id: String,
    cwd: String,
}

/// Find all `claude` processes and trace each to its tmux pane.
async fn find_claude_panes(pane_by_pid: &HashMap<u32, (&str, &str)>) -> Vec<ClaudePane> {
    // Get all process parent relationships in one shot
    let Some(ps_entries) = list_all_processes().await else {
        eprintln!("[poller] failed to list processes");
        return Vec::new();
    };

    eprintln!("[poller] parsed {} processes, {} pane pids", ps_entries.len(), pane_by_pid.len());

    let parent_map: HashMap<u32, u32> = ps_entries
        .iter()
        .map(|e| (e.pid, e.ppid))
        .collect();

    // Find PIDs of actual `claude` binaries (match by process name, not command line)
    let claude_pids: Vec<u32> = ps_entries
        .iter()
        .filter(|e| e.comm == "claude")
        .map(|e| e.pid)
        .collect();

    eprintln!("[poller] found {} claude processes: {:?}", claude_pids.len(), claude_pids);

    let mut result = Vec::new();
    let mut seen_panes: HashSet<String> = HashSet::new();

    for cpid in claude_pids {
        // Walk up the parent chain to find the tmux pane
        let mut current = cpid;
        let mut hops = 0;
        loop {
            if let Some((pane_id, cwd)) = pane_by_pid.get(&current) {
                eprintln!("[poller] claude {} -> pane {} (cwd: {}) in {} hops", cpid, pane_id, cwd, hops);
                if seen_panes.insert(pane_id.to_string()) {
                    result.push(ClaudePane {
                        pane_id: pane_id.to_string(),
                        cwd: cwd.to_string(),
                    });
                }
                break;
            }
            match parent_map.get(&current) {
                Some(&ppid) if ppid != current && ppid != 0 => {
                    current = ppid;
                    hops += 1;
                }
                _ => {
                    eprintln!("[poller] claude {} -> no pane found (stopped at pid {} after {} hops)", cpid, current, hops);
                    break;
                }
            }
        }
    }

    result
}

struct PsEntry {
    pid: u32,
    ppid: u32,
    comm: String,
}

/// List all processes with pid, ppid, and command name.
async fn list_all_processes() -> Option<Vec<PsEntry>> {
    let output = Command::new("ps")
        .args(["-eo", "pid,ppid,comm"])
        .output()
        .await
        .ok()?;

    if !output.status.success() {
        return None;
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    let entries = stdout
        .lines()
        .skip(1) // header
        .filter_map(|line| {
            let mut parts = line.split_whitespace();
            let pid: u32 = parts.next()?.parse().ok()?;
            let ppid: u32 = parts.next()?.parse().ok()?;
            let comm = parts.next()?.to_string();
            // Extract just the binary name from the path
            let comm = comm
                .rsplit('/')
                .next()
                .unwrap_or(&comm)
                .trim_start_matches('-') // login shells show as -zsh
                .to_string();
            Some(PsEntry { pid, ppid, comm })
        })
        .collect();

    Some(entries)
}

struct TmuxPane {
    pane_id: String,
    pane_pid: u32,
    cwd: String,
}

async fn list_tmux_panes() -> Option<Vec<TmuxPane>> {
    let output = Command::new("tmux")
        .args(["list-panes", "-a", "-F", "#{pane_id} #{pane_pid} #{pane_current_path}"])
        .output()
        .await
        .ok()?;

    if !output.status.success() {
        return None;
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    let panes = stdout
        .lines()
        .filter_map(|line| {
            let mut parts = line.splitn(3, ' ');
            let pane_id = parts.next()?.to_string();
            let pane_pid: u32 = parts.next()?.parse().ok()?;
            let cwd = parts.next()?.to_string();
            Some(TmuxPane {
                pane_id,
                pane_pid,
                cwd,
            })
        })
        .collect();

    Some(panes)
}
