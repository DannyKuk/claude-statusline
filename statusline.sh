#!/usr/bin/env bash
# Statusline script (bash port of statusline.ps1)
# model | folder | git branch | 5h rate-limit usage | context usage | team
input=$(cat)

field() { jq -r "$1 // empty" <<<"$input" 2>/dev/null; }

# ---- palette (256-colour; NO_COLOR disables) ------------------------------
c() { [ -n "$NO_COLOR" ] && echo '' || echo "$1"; }
C_MODEL=$(c '38;5;80')    # turquoise - the identity anchor
C_DIR=$(c '38;5;252')     # near-white
C_BRANCH=$(c '38;5;108')  # muted git green
C_SEP=$(c '38;5;240')     # dark grey, recedes
C_LABEL=$(c '38;5;244')   # grey, quieter than the number it labels
C_TEAM=$(c '38;5;141')    # soft purple

ESC=$'\033'
seg() {
  [ -z "$2" ] && return
  if [ -z "$1" ]; then printf '%s' "$2"; else printf '%s[%sm%s%s[0m' "$ESC" "$1" "$2" "$ESC"; fi
}

pct_color() {
  local p=$1
  if   [ "$p" -ge 90 ]; then c '1;38;5;196'  # bold red
  elif [ "$p" -ge 80 ]; then c '38;5;208'    # orange
  elif [ "$p" -ge 60 ]; then c '38;5;220'    # yellow
  else c '38;5;79'; fi                       # turquoise-green
}

# Truncate to a non-negative integer ("37.48" -> 37).
norm_int() {
  local v=${1%%.*}
  [[ "$v" =~ ^[0-9]+$ ]] && echo "$((10#$v))" || echo 0
}

pct_seg() {
  [ -z "$2" ] && return
  local n; n=$(norm_int "$2")
  printf '%s%s' "$(seg "$C_LABEL" "$1 ")" "$(seg "$(pct_color "$n")" "${n}%")"
}

now() {
  if [[ "$STATUSLINE_CLOCK_OVERRIDE" =~ ^[0-9]+$ ]]; then echo "$STATUSLINE_CLOCK_OVERRIDE"; else date +%s; fi
}

# Bare countdown to a unix-epoch target: "2h14m", "14m", "<1m"; '' if absent/past.
until_reset() {
  local t; t=$(norm_int "$1")
  [ "$t" -eq 0 ] && return
  local diff=$(( t - $(now) ))
  [ "$diff" -le 0 ] && return
  local h=$(( diff / 3600 )) m=$(( (diff % 3600) / 60 ))
  if   [ "$h" -gt 0 ]; then printf '%dh%02dm' "$h" "$m"
  elif [ "$m" -gt 0 ]; then printf '%dm' "$m"
  else printf '<1m'; fi
}

cwd=$(field '.workspace.current_dir'); [ -z "$cwd" ] && cwd=$(field '.cwd')

git_branch() {
  local b=''
  [ -n "$cwd" ] && b=$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null)
  [ -n "$b" ] && echo "$b" || field '.workspace.git_worktree'
}

# Claude org name from the local login (not in the statusline JSON).
team() {
  jq -r '.oauthAccount.organizationName // empty' "$HOME/.claude.json" 2>/dev/null
}

label_5h=$(until_reset "$(field '.rate_limits.five_hour.resets_at')")
[ -z "$label_5h" ] && label_5h='5h'

parts=(
  "$(seg "$C_MODEL" "$(field '.model.display_name')")"
  "$(seg "$C_DIR" "$(basename "$cwd" 2>/dev/null)")"
  "$(seg "$C_BRANCH" "$(git_branch)")"
  "$(pct_seg "$label_5h" "$(field '.rate_limits.five_hour.used_percentage')")"
  "$(pct_seg 'ctx' "$(field '.context_window.used_percentage')")"
  "$(seg "$C_TEAM" "$(team)")"
)

sep=$(seg "$C_SEP" ' | ')
out=''
for p in "${parts[@]}"; do
  [ -z "$p" ] && continue
  [ -n "$out" ] && out+=$sep
  out+=$p
done
printf '%s' "$out"

# Spacer row: a ZERO WIDTH SPACE (U+200B) survives trimming where an empty
# line or plain space would be dropped.
printf '\n\xe2\x80\x8b'
exit 0
