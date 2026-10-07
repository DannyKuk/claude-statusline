---
name: slconfig
description: Use when the user runs /slconfig, or asks to show, hide, list or turn on/off segments of the claude-statusline status line (model, folder, branch, 5h, ctx, team, energy).
argument-hint: "[hide|show <segment>...]"
---

# claude-statusline settings

The status line from https://github.com/DannyKuk/claude-statusline reads one
settings file: `~/.claude/claude-statusline.conf`
(`%USERPROFILE%\.claude\claude-statusline.conf` on Windows). Only edit that
file; never `settings.json` or the status line script.

## Format

`#` starts a comment, at the start of a line or after a value. The only
setting is a comma-separated `hide` line:

```ini
hide = energy, team
```

A `hide` line is a non-comment line whose text before the first `=` is `hide`
(any case, any spacing). The template's comment `# ... e.g.  hide = energy, team`
is not one. No file, or an empty `hide =`, shows everything.

| Segment  | What it is                                  |
|----------|---------------------------------------------|
| `model`  | model name                                  |
| `folder` | current folder                              |
| `branch` | git branch                                  |
| `5h`     | 5-hour rate limit usage / reset countdown   |
| `ctx`    | context window usage                        |
| `team`   | Claude organization (or "Personal")         |
| `energy` | session energy estimate (⚡ Wh, 🔋)          |

## Commands

- **`/slconfig`** (no arguments): read the file and list every segment as
  on or off. If the file doesn't exist, everything is on; don't create it.
- **`/slconfig hide <segment>...`** adds segments to the hidden set;
  **`/slconfig show <segment>...`** removes them from it. Other hidden
  segments stay as they are.
- Plain requests ("hide the energy thing", "turn the 5 hour limit back on")
  map to the same actions, using the table to turn descriptions into names.

## Updating the file

1. Map each requested segment to a name from the table (case-insensitive;
   "5 hour limit" is `5h`, "context" is `ctx`). If any can't be mapped, change
   nothing and create nothing: say which are unknown and list the valid names.
2. If the file is missing, create it with this template first:

   ```ini
   # Settings for claude-statusline
   # https://github.com/DannyKuk/claude-statusline
   #
   # Segments: model, folder, branch, 5h, ctx, team, energy
   # List the ones to hide, comma-separated, e.g.  hide = energy, team
   hide =
   ```

3. Read the current hidden set from all `hide` lines (lower-cased, unknown
   names dropped), then add or remove the requested segments.
4. Write it as `hide = a, b` in table order. It replaces the first `hide` line,
   inline comment included; delete any other `hide` lines; leave every other
   line exactly as it is. No `hide` line yet: append one. Showing everything
   leaves `hide =` empty; keep the file.
5. Reply with all seven segments as on/off in one line (e.g.
   `model on · ... · energy off`), and that it applies on the status line's
   next refresh.
