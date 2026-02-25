use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

use crate::session::Session;

pub const SOCKET_PATH: &str = "/tmp/bottycall.sock";

/// First line sent by a connecting client to identify itself.
#[derive(Debug, Deserialize)]
#[serde(tag = "type")]
pub enum ClientHello {
    #[serde(rename = "report")]
    Report(HookReport),
    #[serde(rename = "subscribe")]
    Subscribe,
}

/// Sent by the hook reporter to the daemon.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HookReport {
    pub session_id: String,
    pub hook_event_name: String,
    #[serde(default)]
    pub cwd: Option<String>,
    #[serde(default)]
    pub message: Option<String>,
    #[serde(default)]
    pub stop_hook_active: Option<bool>,
    #[serde(default)]
    pub tool_name: Option<String>,
    #[serde(default)]
    pub tmux_pane: Option<String>,
    #[serde(default)]
    pub transcript_path: Option<String>,
    #[serde(default)]
    pub ts: Option<DateTime<Utc>>,
}

/// Messages sent from the daemon to TUI subscribers.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum ServerMessage {
    #[serde(rename = "snapshot")]
    Snapshot { sessions: Vec<Session> },
    #[serde(rename = "update")]
    Update { session: Session },
    #[serde(rename = "remove")]
    Remove { session_id: String },
}
