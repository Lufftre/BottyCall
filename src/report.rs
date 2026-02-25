use std::io::{Read, Write};
use std::os::unix::net::UnixStream;
use std::time::Duration;

use crate::protocol::SOCKET_PATH;

/// Hook reporter entry point. Reads stdin, extracts fields, sends to daemon.
/// All errors are silently ignored — must never block Claude Code.
pub fn run(event: &str) {
    let _ = run_inner(event);
}

fn debug_log(event: &str, msg: &str) {
    use std::io::Write;
    if let Ok(mut f) = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open("/tmp/bottycall-debug.log")
    {
        let _ = writeln!(f, "[{}] {}: {}", chrono::Utc::now().format("%H:%M:%S"), event, msg);
    }
}

fn run_inner(event: &str) -> Option<()> {
    // Read stdin (the hook payload from Claude Code)
    let mut input = String::new();
    std::io::stdin().read_to_string(&mut input).ok()?;

    debug_log(event, &format!("raw stdin: {}", input.trim()));

    let hook: serde_json::Value = serde_json::from_str(&input).ok()?;

    // Skip the parent "startup" session — only the "resume" session gets real events
    if event == "SessionStart" {
        if hook.get("source").and_then(|v| v.as_str()) == Some("startup") {
            return Some(());
        }
    }

    let session_id = hook.get("session_id")?.as_str()?;
    let cwd = hook.get("cwd").and_then(|v| v.as_str());
    let message = hook.get("message").and_then(|v| v.as_str());
    let stop_hook_active = hook.get("stop_hook_active").and_then(|v| v.as_bool());
    let tool_name = hook.get("tool_name").and_then(|v| v.as_str());

    // Get tmux pane from environment
    let tmux_pane = std::env::var("TMUX_PANE").ok();

    // Build compact report JSON
    let mut report = serde_json::json!({
        "type": "report",
        "session_id": session_id,
        "hook_event_name": event,
    });
    let obj = report.as_object_mut()?;
    if let Some(v) = cwd {
        obj.insert("cwd".into(), v.into());
    }
    if let Some(v) = message {
        obj.insert("message".into(), v.into());
    }
    if let Some(v) = stop_hook_active {
        obj.insert("stop_hook_active".into(), v.into());
    }
    if let Some(v) = tool_name {
        obj.insert("tool_name".into(), v.into());
    }
    if let Some(v) = &tmux_pane {
        obj.insert("tmux_pane".into(), v.clone().into());
    }
    obj.insert("ts".into(), chrono::Utc::now().to_rfc3339().into());

    let mut payload = serde_json::to_string(&report).ok()?;
    payload.push('\n');

    // Connect to daemon and send
    let mut stream = UnixStream::connect(SOCKET_PATH).ok()?;
    stream
        .set_write_timeout(Some(Duration::from_millis(100)))
        .ok()?;
    stream.write_all(payload.as_bytes()).ok()?;
    stream.flush().ok()?;

    Some(())
}
