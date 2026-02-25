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
    #[serde(default)]
    pub git_repo: Option<String>,
    #[serde(default)]
    pub git_branch: Option<String>,
    /// Token count from live tmux pane capture of Claude Code's status bar.
    #[serde(default)]
    pub input_tokens: u64,
    #[serde(default)]
    pub output_tokens: u64,
}

/// Resolve the git repository root for a working directory.
/// Uses --git-common-dir so that worktrees of the same repo share one root.
pub fn git_repo_from_cwd(cwd: &str) -> Option<String> {
    let output = std::process::Command::new("git")
        .args(["-C", cwd, "rev-parse", "--path-format=absolute", "--git-common-dir"])
        .output()
        .ok()?;

    if !output.status.success() {
        return None;
    }

    let git_dir = String::from_utf8(output.stdout).ok()?;
    let git_dir = git_dir.trim();
    let path = std::path::Path::new(git_dir);
    let abs = if path.is_absolute() {
        path.to_path_buf()
    } else {
        std::path::Path::new(cwd).join(path)
    };

    // git_dir is e.g. "/path/to/repo/.git" — parent is the repo root
    abs.parent()
        .and_then(|p| p.to_str())
        .map(|s| s.to_string())
}

/// Resolve the current git branch for a working directory.
pub fn git_branch_from_cwd(cwd: &str) -> Option<String> {
    let output = std::process::Command::new("git")
        .args(["-C", cwd, "rev-parse", "--abbrev-ref", "HEAD"])
        .output()
        .ok()?;

    if !output.status.success() {
        return None;
    }

    let branch = String::from_utf8(output.stdout).ok()?;
    let branch = branch.trim();
    if branch.is_empty() || branch == "HEAD" {
        return None;
    }
    Some(branch.to_string())
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

/// Format a token count as a compact human-readable string (e.g. "12k", "1.4M").
pub fn format_tokens(n: u64) -> String {
    if n == 0 {
        return String::new();
    }
    if n < 1_000 {
        return format!("{n}");
    }
    if n < 10_000 {
        return format!("{:.1}k", n as f64 / 1_000.0);
    }
    if n < 1_000_000 {
        return format!("{}k", n / 1_000);
    }
    format!("{:.1}M", n as f64 / 1_000_000.0)
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
