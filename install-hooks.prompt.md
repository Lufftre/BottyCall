Merge the hooks from `hooks.json` in this repo into `~/.claude/settings.json`.

- Read the existing `~/.claude/settings.json` (create it if it doesn't exist)
- Read `hooks.json` from this repo
- Merge each hook event into the existing `hooks` object, appending to any existing arrays for the same event — do not overwrite hooks the user already has
- Write back the merged result
