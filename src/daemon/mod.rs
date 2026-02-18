mod listener;
mod poller;
pub mod state;

use std::sync::Arc;

use tokio::net::UnixListener;
use tokio::signal;
use tokio::sync::{Mutex, broadcast};

use crate::protocol::{SOCKET_PATH, ServerMessage};

use state::SessionMap;

pub async fn run() {
    // Clean up stale socket
    let _ = std::fs::remove_file(SOCKET_PATH);

    let listener = UnixListener::bind(SOCKET_PATH).expect("failed to bind socket");
    eprintln!("bottycall daemon listening on {SOCKET_PATH}");

    let state = Arc::new(Mutex::new(SessionMap::new()));
    let (tx, _rx) = broadcast::channel::<ServerMessage>(256);

    // Spawn the socket accept loop
    let accept_state = Arc::clone(&state);
    let accept_tx = tx.clone();
    tokio::spawn(async move {
        listener::accept_loop(listener, accept_state, accept_tx).await;
    });

    // Spawn the tmux poller
    let poll_state = Arc::clone(&state);
    let poll_tx = tx.clone();
    tokio::spawn(async move {
        poller::poll_loop(poll_state, poll_tx).await;
    });

    // Wait for shutdown signal
    tokio::select! {
        _ = signal::ctrl_c() => {
            eprintln!("\nshutting down...");
        }
        _ = async {
            let mut sigterm = signal::unix::signal(signal::unix::SignalKind::terminate())
                .expect("failed to register SIGTERM handler");
            sigterm.recv().await
        } => {
            eprintln!("\nreceived SIGTERM, shutting down...");
        }
    }

    // Cleanup
    let _ = std::fs::remove_file(SOCKET_PATH);
}
