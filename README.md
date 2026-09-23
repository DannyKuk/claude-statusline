Claude Code status line (from Danny's Windows machine)
======================================================

statusline.ps1 is the working PowerShell status line script. On Windows it is wired
up in ~/.claude/settings.json as:

  "statusLine": {
    "type": "command",
    "command": "powershell.exe -NoProfile -File \"C:\Users\danny\.claude\statusline.ps1\"",
    "refreshInterval": 60
  }

What it shows: model | folder | git branch | 5h rate-limit usage | context usage
- The 5h label becomes a countdown to the window reset (e.g. "2h14m 37%"), falling back to "5h".
- Percentages: turquoise < 60%, yellow >= 60%, orange >= 80%, bold red >= 90%.
- Separators are dark grey " | "; colours are 256-colour codes; NO_COLOR disables colour.
- Prints a second line containing only U+200B (zero width space) as a spacer row.

To install on macOS: port this to a bash script in ~/.claude/statusline.sh
(chmod +x) and point statusLine.command at it, keeping refreshInterval 60.
