---
name: slconfig
description: Use when the user runs /slconfig, or asks to show, hide, list or turn on/off segments of the claude-statusline status line (model, folder, branch, 5h, ctx, team, energy).
argument-hint: "[segment...]"
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
- **`/slconfig <segment>...`** toggles each named segment: hidden ones
  come back, shown ones are hidden. Other segments stay as they are.
- Plain requests say which way ("hide the energy thing", "turn the 5 hour
  limit back on"), so they only hide or only show, never toggle. The same
  goes for arguments like `/slconfig hide energy`. A segment already in the
  requested state stays as it is.

## Updating the file

1. Map each requested segment to a name from the table (case-insensitive;
   "5 hour limit" is `5h`, "context" is `ctx`). If any can't be mapped, change
   nothing and create nothing: say which are unknown and list the valid names.
   A segment named twice counts once.
2. Read the current hidden set from all `hide` lines (lower-cased, unknown
   names dropped; no file means nothing hidden), then apply the toggle, hide
   or show.
3. If the hidden set didn't change, write nothing and create nothing; say the
   segments were already in that state and give only the on/off line from
   step 6.
4. If the file is missing, create it with this template first:

   ```ini
   # Settings for claude-statusline
   # https://github.com/DannyKuk/claude-statusline
   #
   # Segments: model, folder, branch, 5h, ctx, team, energy
   # List the ones to hide, comma-separated, e.g.  hide = energy, team
   hide =
   ```

5. Write the new hidden set as `hide = a, b` in table order. It replaces the first `hide` line,
   inline comment included; delete any other `hide` lines; leave every other
   line exactly as it is. No `hide` line yet: append one. Showing everything
   leaves `hide =` empty; keep the file.
6. Reply with all seven segments as on/off in one line (e.g.
   `model on · ... · energy off`), and that it applies on the status line's
   next refresh.
