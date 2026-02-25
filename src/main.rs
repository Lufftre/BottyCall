mod daemon;
mod protocol;
mod report;
mod session;
mod tui;

use clap::{Parser, Subcommand};

#[derive(Parser)]
#[command(name = "bottycall", about = "Claude Code session monitor")]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Start the monitoring daemon
    Daemon,
    /// Report a hook event (called by Claude Code hooks, reads stdin)
    Report {
        /// The hook event name (e.g. SessionStart, Stop, PreToolUse)
        #[arg(long)]
        event: String,
    },
    /// Launch the interactive TUI dashboard
    Tui,
}

fn main() {
    let cli = Cli::parse();

    match cli.command {
        Command::Daemon => {
            // Ensure Homebrew / common bin dirs are in PATH so the poller
            // can find tmux and git when launched via launchd.
            let path = std::env::var("PATH").unwrap_or_default();
            unsafe {
                std::env::set_var(
                    "PATH",
                    format!("/opt/homebrew/bin:/usr/local/bin:{path}"),
                );
            }

            let rt = tokio::runtime::Runtime::new().expect("failed to create tokio runtime");
            rt.block_on(daemon::run());
        }
        Command::Report { event } => {
            report::run(&event);
        }
        Command::Tui => {
            let rt = tokio::runtime::Runtime::new().expect("failed to create tokio runtime");
            rt.block_on(tui::run());
        }
    }
}
