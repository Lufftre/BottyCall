# BottyCall

A lightweight daemon that monitors your Claude Code sessions and shows their status in a TUI dashboard.

Tracks session state (working, idle, needs attention) via Claude Code hooks, with tmux pane discovery as fallback.

## Install

```
make install
```

Builds the binary to `~/.local/bin` and starts a launchd daemon that runs on login.

## Hooks

Set up Claude Code hooks so the daemon receives session events:

```
claude /install-hooks.prompt.md
```

## Usage

```
bottycall tui
```

Or bind it to a tmux popup for quick access — the install prompt can set that up too.

## Uninstall

```
make uninstall
```
