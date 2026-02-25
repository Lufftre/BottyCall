use std::collections::HashMap;
use std::io::{Read, Seek, SeekFrom};

use chrono::Utc;

use crate::protocol::{HookReport, ServerMessage};
use crate::session::{Session, Status, git_branch_from_cwd, git_repo_from_cwd, slug_from_cwd};

/// Holds all tracked sessions keyed by session_id.
pub struct SessionMap {
    sessions: HashMap<String, Session>,
}

impl SessionMap {
    pub fn new() -> Self {
        Self {
            sessions: HashMap::new(),
        }
    }

    pub fn sessions(&self) -> Vec<Session> {
        self.sessions.values().cloned().collect()
    }

    /// Apply a hook report and return server messages to broadcast.
    pub fn apply_report(&mut self, report: &HookReport) -> Vec<ServerMessage> {
        let event = report.hook_event_name.as_str();
        let now = report.ts.unwrap_or_else(Utc::now);

        // SessionEnd -> remove
        if event == "SessionEnd" {
            if self.sessions.remove(&report.session_id).is_some() {
                return vec![ServerMessage::Remove {
                    session_id: report.session_id.clone(),
                }];
            }
            return vec![];
        }

        // If this hook report has a tmux_pane, evict any polled session occupying it
        let polled_remove = if let Some(pane) = &report.tmux_pane {
            let polled_id = self
                .sessions
                .values()
                .find(|s| {
                    s.session_id.starts_with("polled-")
                        && s.tmux_pane.as_ref() == Some(pane)
                })
                .map(|s| s.session_id.clone());
            if let Some(id) = polled_id {
                self.sessions.remove(&id);
                Some(ServerMessage::Remove { session_id: id })
            } else {
                None
            }
        } else {
            None
        };

        let session = self
            .sessions
            .entry(report.session_id.clone())
            .or_insert_with(|| {
                let cwd = report.cwd.clone().unwrap_or_default();
                let (slug, git_repo, git_branch) = if cwd.is_empty() {
                    (report.session_id.chars().take(8).collect(), None, None)
                } else {
                    (slug_from_cwd(&cwd), git_repo_from_cwd(&cwd), git_branch_from_cwd(&cwd))
                };
                Session {
                    session_id: report.session_id.clone(),
                    slug,
                    status: Status::Idle,
                    last_activity: now,
                    cwd: report.cwd.clone(),
                    tmux_pane: report.tmux_pane.clone(),
                    git_repo,
                    git_branch,
                    input_tokens: 0,
                    output_tokens: 0,
                    transcript_path: report.transcript_path.clone(),
                    transcript_offset: 0,
                }
            });

        // Update fields if provided
        if let Some(cwd) = &report.cwd {
            if session.cwd.as_ref() != Some(cwd) {
                session.cwd = Some(cwd.clone());
                session.slug = slug_from_cwd(cwd);
                session.git_repo = git_repo_from_cwd(cwd);
                session.git_branch = git_branch_from_cwd(cwd);
            }
        }
        if report.tmux_pane.is_some() {
            session.tmux_pane = report.tmux_pane.clone();
        }
        if report.transcript_path.is_some() {
            session.transcript_path = report.transcript_path.clone();
        }

        // State machine transitions
        let new_status = match event {
            "SessionStart" => Some(Status::Idle),
            "UserPromptSubmit" | "PreToolUse" => Some(Status::Working),
            "Stop" => Some(Status::Idle),
            "Notification" => {
                // Check if it's a permission prompt
                if report
                    .message
                    .as_deref()
                    .map(|m| m.contains("permission"))
                    .unwrap_or(false)
                {
                    Some(Status::Attention)
                } else {
                    None
                }
            }
            "PermissionRequest" => Some(Status::Attention),
            "PostToolUse" => Some(Status::Working),
            _ => None,
        };

        if let Some(status) = new_status {
            session.status = status;
        }
        session.last_activity = now;

        // On Stop, read new transcript entries and accumulate token usage
        if event == "Stop" {
            if let Some(path) = session.transcript_path.clone() {
                let (din, dout) = read_transcript_usage(&path, &mut session.transcript_offset);
                session.input_tokens += din;
                session.output_tokens += dout;
            }
        }

        let mut msgs = Vec::new();
        if let Some(rm) = polled_remove {
            msgs.push(rm);
        }
        msgs.push(ServerMessage::Update {
            session: session.clone(),
        });
        msgs
    }

    /// Register a session discovered by the poller.
    pub fn register_polled(
        &mut self,
        session_id: String,
        cwd: String,
        tmux_pane: String,
    ) -> Option<ServerMessage> {
        if self.sessions.contains_key(&session_id) {
            return None;
        }

        // Don't create a polled session if a hook-reported session already owns this pane
        let pane_taken = self.sessions.values().any(|s| {
            !s.session_id.starts_with("polled-") && s.tmux_pane.as_ref() == Some(&tmux_pane)
        });
        if pane_taken {
            return None;
        }

        let slug = slug_from_cwd(&cwd);
        let git_repo = git_repo_from_cwd(&cwd);
        let git_branch = git_branch_from_cwd(&cwd);
        let session = Session {
            session_id: session_id.clone(),
            slug,
            status: Status::Idle,
            last_activity: Utc::now(),
            cwd: Some(cwd),
            tmux_pane: Some(tmux_pane),
            git_repo,
            git_branch,
            input_tokens: 0,
            output_tokens: 0,
            transcript_path: None,
            transcript_offset: 0,
        };
        self.sessions.insert(session_id, session.clone());
        Some(ServerMessage::Update { session })
    }

    /// Remove a session and return a Remove message if it existed.
    pub fn remove(&mut self, session_id: &str) -> Option<ServerMessage> {
        self.sessions.remove(session_id).map(|_| ServerMessage::Remove {
            session_id: session_id.to_string(),
        })
    }

    /// Get all known tmux panes mapped to their session_ids.
    pub fn pane_session_map(&self) -> HashMap<String, String> {
        self.sessions
            .values()
            .filter_map(|s| {
                s.tmux_pane
                    .as_ref()
                    .map(|p| (p.clone(), s.session_id.clone()))
            })
            .collect()
    }
}

/// Read new assistant entries from the transcript JSONL file starting at `offset`,
/// returning (input_tokens, output_tokens) and advancing the offset.
/// Input tokens include raw input plus cache reads and cache writes.
/// Errors are silently ignored — token counting is best-effort.
fn read_transcript_usage(path: &str, offset: &mut u64) -> (u64, u64) {
    let mut file = match std::fs::File::open(path) {
        Ok(f) => f,
        Err(_) => return (0, 0),
    };

    if file.seek(SeekFrom::Start(*offset)).is_err() {
        return (0, 0);
    }

    let mut buf = String::new();
    if file.read_to_string(&mut buf).is_err() {
        return (0, 0);
    }

    *offset += buf.len() as u64;

    let mut input_tokens = 0u64;
    let mut output_tokens = 0u64;

    for line in buf.lines() {
        let Ok(entry) = serde_json::from_str::<serde_json::Value>(line) else {
            continue;
        };
        if entry.get("type").and_then(|v| v.as_str()) != Some("assistant") {
            continue;
        }
        let Some(usage) = entry.get("message").and_then(|m| m.get("usage")) else {
            continue;
        };
        let tok = |key: &str| usage.get(key).and_then(|v| v.as_u64()).unwrap_or(0);
        input_tokens += tok("input_tokens")
            + tok("cache_read_input_tokens")
            + tok("cache_creation_input_tokens");
        output_tokens += tok("output_tokens");
    }

    (input_tokens, output_tokens)
}
