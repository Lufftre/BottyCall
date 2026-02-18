use crate::protocol::ServerMessage;
use crate::session::{Session, disambiguate_slugs};

pub struct App {
    pub sessions: Vec<Session>,
    pub cursor: usize,
    pub should_quit: bool,
}

impl App {
    pub fn new() -> Self {
        Self {
            sessions: Vec::new(),
            cursor: 0,
            should_quit: false,
        }
    }

    /// Apply a server message and update local state.
    pub fn apply(&mut self, msg: ServerMessage) {
        match msg {
            ServerMessage::Snapshot { sessions } => {
                self.sessions = sessions;
            }
            ServerMessage::Update { session } => {
                if let Some(existing) = self
                    .sessions
                    .iter_mut()
                    .find(|s| s.session_id == session.session_id)
                {
                    *existing = session;
                } else {
                    self.sessions.push(session);
                }
            }
            ServerMessage::Remove { session_id } => {
                self.sessions.retain(|s| s.session_id != session_id);
            }
        }

        // Sort: Attention first, then Working, then Idle
        self.sessions.sort_by(|a, b| {
            fn priority(s: &Session) -> u8 {
                match s.status {
                    crate::session::Status::Attention => 0,
                    crate::session::Status::Working => 1,
                    crate::session::Status::Idle => 2,
                }
            }
            priority(a)
                .cmp(&priority(b))
                .then(a.slug.cmp(&b.slug))
        });

        // Disambiguate slugs
        disambiguate_slugs(&mut self.sessions);

        // Clamp cursor
        if !self.sessions.is_empty() {
            self.cursor = self.cursor.min(self.sessions.len() - 1);
        } else {
            self.cursor = 0;
        }
    }

    pub fn move_up(&mut self) {
        if self.cursor > 0 {
            self.cursor -= 1;
        }
    }

    pub fn move_down(&mut self) {
        if !self.sessions.is_empty() {
            self.cursor = (self.cursor + 1) % self.sessions.len();
        }
    }

    /// Get the tmux pane of the selected session.
    pub fn selected_pane(&self) -> Option<&str> {
        self.sessions
            .get(self.cursor)
            .and_then(|s| s.tmux_pane.as_deref())
    }
}
