mod app;
mod ui;

use std::io;

use crossterm::event::{self, Event, KeyCode, KeyEventKind};
use crossterm::terminal::{
    EnterAlternateScreen, LeaveAlternateScreen, disable_raw_mode, enable_raw_mode,
};
use ratatui::DefaultTerminal;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::UnixStream;

use crate::protocol::{SOCKET_PATH, ServerMessage};

use app::App;

pub async fn run() {
    if let Err(e) = run_inner().await {
        eprintln!("tui error: {e}");
    }
}

async fn run_inner() -> anyhow::Result<()> {
    // Connect to daemon
    let stream = UnixStream::connect(SOCKET_PATH).await?;
    let (reader, mut writer) = stream.into_split();
    let mut reader = BufReader::new(reader);

    // Send subscribe hello
    writer.write_all(b"{\"type\":\"subscribe\"}\n").await?;

    // Setup terminal
    enable_raw_mode()?;
    crossterm::execute!(io::stdout(), EnterAlternateScreen)?;
    let mut terminal = ratatui::init();

    let mut app = App::new();
    let result = event_loop(&mut terminal, &mut app, &mut reader).await;

    // Restore terminal
    ratatui::restore();
    disable_raw_mode()?;
    crossterm::execute!(io::stdout(), LeaveAlternateScreen)?;

    result
}

async fn event_loop(
    terminal: &mut DefaultTerminal,
    app: &mut App,
    reader: &mut BufReader<tokio::net::unix::OwnedReadHalf>,
) -> anyhow::Result<()> {
    let mut line_buf = String::new();

    // Initial draw
    terminal.draw(|f| ui::draw(f, app))?;

    loop {
        tokio::select! {
            // Read from daemon socket
            result = reader.read_line(&mut line_buf) => {
                match result {
                    Ok(0) => {
                        // Daemon disconnected
                        break;
                    }
                    Ok(_) => {
                        if let Ok(msg) = serde_json::from_str::<ServerMessage>(line_buf.trim()) {
                            app.apply(msg);
                            terminal.draw(|f| ui::draw(f, app))?;
                        }
                        line_buf.clear();
                    }
                    Err(e) => {
                        return Err(e.into());
                    }
                }
            }

            // Handle keyboard input (poll with timeout for responsiveness)
            _ = tokio::task::spawn_blocking(|| event::poll(std::time::Duration::from_millis(100))) => {
                // Check for available events without blocking
                while event::poll(std::time::Duration::ZERO)? {
                    if let Event::Key(key) = event::read()? {
                        if key.kind != KeyEventKind::Press {
                            continue;
                        }
                        match key.code {
                            KeyCode::Char('q') | KeyCode::Esc => {
                                app.should_quit = true;
                            }
                            KeyCode::Char('j') | KeyCode::Down => {
                                app.move_down();
                            }
                            KeyCode::Char('k') | KeyCode::Up => {
                                app.move_up();
                            }
                            KeyCode::Enter => {
                                if let Some(pane) = app.selected_pane() {
                                    switch_to_pane(pane);
                                }
                                app.move_down();
                            }
                            _ => {}
                        }
                    }
                }

                if app.should_quit {
                    break;
                }

                terminal.draw(|f| ui::draw(f, app))?;
            }
        }
    }

    Ok(())
}

fn switch_to_pane(pane_id: &str) {
    // switch-client handles cross-session jumps (select-pane/select-window don't)
    let _ = std::process::Command::new("tmux")
        .args(["switch-client", "-t", pane_id])
        .status();
}
