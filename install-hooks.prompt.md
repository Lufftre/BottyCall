Merge the hooks from `hooks.json` in this repo into `~/.claude/settings.json`.

- Read the existing `~/.claude/settings.json` (create it if it doesn't exist)
- Read `hooks.json` from this repo
- Merge each hook event into the existing `hooks` object, appending to any existing arrays for the same event — do not overwrite hooks the user already has
- Write back the merged result

Then ask the user if they want a hotkey to open the BottyCall TUI in a tmux popup.

If yes, add these two lines to their config files:

1. Ghostty (`~/.config/ghostty/config`) — a keybind that sends Ctrl+_ to the terminal:

       keybind = cmd+ö=text:\x1f

2. tmux (`~/.config/tmux/tmux.conf`) — maps Ctrl+_ to a popup running the TUI:

       bind-key -n C-_ display-popup -E -w 60% -h 40% "bottycall tui"

Check each config file first and skip any binding that already exists. Let the user pick a different key if they prefer.
