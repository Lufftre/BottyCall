use std::sync::Arc;

use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::{UnixListener, UnixStream};
use tokio::sync::{Mutex, broadcast};

use crate::protocol::{ClientHello, ServerMessage};

use super::state::SessionMap;

/// Accept connections on the Unix socket and dispatch them.
pub async fn accept_loop(
    listener: UnixListener,
    state: Arc<Mutex<SessionMap>>,
    tx: broadcast::Sender<ServerMessage>,
) {
    loop {
        match listener.accept().await {
            Ok((stream, _addr)) => {
                let state = Arc::clone(&state);
                let tx = tx.clone();
                tokio::spawn(async move {
                    if let Err(e) = handle_connection(stream, state, tx).await {
                        eprintln!("connection error: {e}");
                    }
                });
            }
            Err(e) => {
                eprintln!("accept error: {e}");
            }
        }
    }
}

async fn handle_connection(
    stream: UnixStream,
    state: Arc<Mutex<SessionMap>>,
    tx: broadcast::Sender<ServerMessage>,
) -> anyhow::Result<()> {
    let (reader, writer) = stream.into_split();
    let mut reader = BufReader::new(reader);
    let mut line = String::new();

    // Read the client hello line
    reader.read_line(&mut line).await?;
    let line = line.trim();
    if line.is_empty() {
        return Ok(());
    }

    let hello: ClientHello = serde_json::from_str(line)?;

    match hello {
        ClientHello::Report(report) => {
            let mut map = state.lock().await;
            for msg in map.apply_report(&report) {
                let _ = tx.send(msg);
            }
        }
        ClientHello::Subscribe => {
            handle_subscriber(writer, state, tx).await?;
        }
    }

    Ok(())
}

async fn handle_subscriber(
    mut writer: tokio::net::unix::OwnedWriteHalf,
    state: Arc<Mutex<SessionMap>>,
    tx: broadcast::Sender<ServerMessage>,
) -> anyhow::Result<()> {
    // Send initial snapshot
    let snapshot = {
        let map = state.lock().await;
        ServerMessage::Snapshot {
            sessions: map.sessions(),
        }
    };
    let mut data = serde_json::to_string(&snapshot)?;
    data.push('\n');
    writer.write_all(data.as_bytes()).await?;

    // Stream updates
    let mut rx = tx.subscribe();
    loop {
        match rx.recv().await {
            Ok(msg) => {
                let mut data = serde_json::to_string(&msg)?;
                data.push('\n');
                if writer.write_all(data.as_bytes()).await.is_err() {
                    break; // Client disconnected
                }
            }
            Err(broadcast::error::RecvError::Lagged(n)) => {
                eprintln!("subscriber lagged by {n} messages, sending fresh snapshot");
                let snapshot = {
                    let map = state.lock().await;
                    ServerMessage::Snapshot {
                        sessions: map.sessions(),
                    }
                };
                let mut data = serde_json::to_string(&snapshot)?;
                data.push('\n');
                if writer.write_all(data.as_bytes()).await.is_err() {
                    break;
                }
            }
            Err(broadcast::error::RecvError::Closed) => break,
        }
    }

    Ok(())
}
