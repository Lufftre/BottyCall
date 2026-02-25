use chrono::Utc;
use ratatui::Frame;
use ratatui::layout::{Constraint, Layout, Rect};
use ratatui::style::{Color, Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, Borders, Cell, Paragraph, Row, Table};

use crate::session::{Status, format_tokens, relative_time};

use super::app::App;

pub fn draw(f: &mut Frame, app: &App) {
    let chunks = Layout::vertical([
        Constraint::Length(1), // title bar
        Constraint::Min(3),   // table
        Constraint::Length(1), // help line
    ])
    .split(f.area());

    draw_title(f, chunks[0], app);
    draw_table(f, chunks[1], app);
    draw_help(f, chunks[2]);
}

fn draw_title(f: &mut Frame, area: Rect, app: &App) {
    let count = app.sessions.len();
    let left = Span::styled(
        " BottyCall",
        Style::default()
            .fg(Color::Cyan)
            .add_modifier(Modifier::BOLD),
    );
    let right = Span::styled(
        format!("{count} session{} ", if count == 1 { "" } else { "s" }),
        Style::default().fg(Color::DarkGray),
    );

    // Pad the middle
    let pad = area
        .width
        .saturating_sub(left.width() as u16 + right.width() as u16);
    let middle = Span::raw(" ".repeat(pad as usize));

    let line = Line::from(vec![left, middle, right]);
    f.render_widget(Paragraph::new(line), area);
}

fn draw_table(f: &mut Frame, area: Rect, app: &App) {
    let now = Utc::now();

    let header = Row::new(vec![
        Cell::from(" Session").style(Style::default().add_modifier(Modifier::BOLD)),
        Cell::from("Status").style(Style::default().add_modifier(Modifier::BOLD)),
        Cell::from("Tokens").style(Style::default().add_modifier(Modifier::BOLD)),
        Cell::from("Last Activity").style(Style::default().add_modifier(Modifier::BOLD)),
    ])
    .height(1);

    let rows: Vec<Row> = app
        .sessions
        .iter()
        .enumerate()
        .map(|(i, session)| {
            let selected = i == app.cursor;
            let marker = if selected { ">" } else { " " };
            let name = format!("{marker} {}", session.slug);

            let status_color = match session.status {
                Status::Working => Color::Yellow,
                Status::Attention => Color::Magenta,
                Status::Idle => Color::Green,
            };

            let status_text = format!("{} {}", session.status.icon(), session.status.label());
            let token_text = format_tokens(session.input_tokens + session.output_tokens);
            let time_text = relative_time(session.last_activity, now);

            let style = if selected {
                Style::default().add_modifier(Modifier::BOLD)
            } else {
                Style::default()
            };

            Row::new(vec![
                Cell::from(name).style(style),
                Cell::from(status_text).style(Style::default().fg(status_color)),
                Cell::from(token_text).style(Style::default().fg(Color::DarkGray)),
                Cell::from(time_text).style(Style::default().fg(Color::Gray)),
            ])
        })
        .collect();

    let widths = [
        Constraint::Percentage(40),
        Constraint::Percentage(22),
        Constraint::Percentage(12),
        Constraint::Percentage(26),
    ];

    let table = Table::new(rows, widths)
        .header(header)
        .block(Block::default().borders(Borders::TOP));

    f.render_widget(table, area);
}

fn draw_help(f: &mut Frame, area: Rect) {
    let help = Line::from(vec![
        Span::styled(" j/k", Style::default().fg(Color::Cyan)),
        Span::raw(" navigate  "),
        Span::styled("Enter", Style::default().fg(Color::Cyan)),
        Span::raw(" switch  "),
        Span::styled("q", Style::default().fg(Color::Cyan)),
        Span::raw(" quit"),
    ]);
    f.render_widget(Paragraph::new(help), area);
}
