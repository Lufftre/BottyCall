use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum Status {
    Idle,
    Working,
    Attention,
}

impl Status {
    pub fn icon(&self) -> &'static str {
        match self {
            Status::Idle => "✓",
            Status::Working => "⚡",
            Status::Attention => "💬",
        }
    }

    pub fn label(&self) -> &'static str {
        match self {
            Status::Idle => "Idle",
            Status::Working => "Working",
            Status::Attention => "Attention",
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Session {
    pub session_id: String,
    pub slug: String,
    pub status: Status,
    pub last_activity: DateTime<Utc>,
    #[serde(default)]
    pub cwd: Option<String>,
    #[serde(default)]
    pub tmux_pane: Option<String>,
}

/// Derive a display slug from the working directory path.
pub fn slug_from_cwd(cwd: &str) -> String {
    std::path::Path::new(cwd)
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("unknown")
        .to_string()
}

/// Disambiguate duplicate slugs by appending a short session_id prefix.
pub fn disambiguate_slugs(sessions: &mut [Session]) {
    // Count slug occurrences
    let mut counts: HashMap<String, usize> = HashMap::new();
    for s in sessions.iter() {
        *counts.entry(s.slug.clone()).or_default() += 1;
    }

    // For any duplicated slug, append [xxxx] from session_id
    for s in sessions.iter_mut() {
        if counts.get(&s.slug).copied().unwrap_or(0) > 1 {
            let prefix: String = s.session_id.chars().take(4).collect();
            // Strip any existing disambiguation suffix first
            if let Some(base) = s.slug.split(" [").next() {
                s.slug = format!("{base} [{prefix}]");
            }
        }
    }
}

/// Format a duration as a human-readable relative time string.
pub fn relative_time(from: DateTime<Utc>, now: DateTime<Utc>) -> String {
    let secs = (now - from).num_seconds().max(0);
    if secs < 5 {
        "just now".to_string()
    } else if secs < 60 {
        format!("{secs}s")
    } else if secs < 3600 {
        format!("{}m", secs / 60)
    } else if secs < 86400 {
        format!("{}h", secs / 3600)
    } else {
        format!("{}d", secs / 86400)
    }
}
