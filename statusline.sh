#!/usr/bin/env bash
# Statusline script (bash port of statusline.ps1)
# model | folder | git branch + state | 5h rate-limit usage | weekly limit (from 80%) | context usage | team | energy
input=$(cat)

field() { jq -r "$1 // empty" <<<"$input" 2>/dev/null; }

# ---- settings -------------------------------------------------------------
# Segments named on a "hide = a, b" line in ~/.claude/claude-statusline.conf
# (or $STATUSLINE_CONFIG) are skipped, not just blanked, so hiding "energy" also
# skips the transcript parse. "#" starts a comment. No file shows everything.
config=${STATUSLINE_CONFIG:-$HOME/.claude/claude-statusline.conf}
hidden=$'\n'$(awk '{ l = tolower($0) } l ~ /^[[:space:]]*hide[[:space:]]*=/ {
    sub(/^[^=]*=/, "", l); sub(/#.*/, "", l)
    n = split(l, a, ",")
    for (i = 1; i <= n; i++) { gsub(/[[:space:]]/, "", a[i]); if (a[i] != "") print a[i] }
  }' "$config" 2>/dev/null)$'\n'
shown() { [[ $hidden != *$'\n'"$1"$'\n'* ]]; }

# ---- palette (256-colour; NO_COLOR disables) ------------------------------
c() { [ -n "$NO_COLOR" ] && echo '' || echo "$1"; }
C_MODEL=$(c '38;5;80')    # turquoise - the identity anchor
C_DIR=$(c '38;5;252')     # near-white
C_BRANCH=$(c '38;5;108')  # muted git green
C_DIRTY=$(c '38;5;215')   # soft orange - uncommitted changes
C_SEP=$(c '38;5;240')     # dark grey, recedes
C_LABEL=$(c '38;5;244')   # grey, quieter than the number it labels
C_TEAM=$(c '38;5;141')    # soft purple
C_ENERGY=$(c '38;5;179')  # soft amber

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

# Branch name plus its state: "*" for uncommitted changes (untracked files
# included), and ↑/↓ for commits ahead of/behind the upstream as of the last
# fetch. One status call covers both; --no-optional-locks keeps a refresh from
# contending with git commands Claude runs at the same moment.
branch_seg() {
  local st='' line b='' dirty='' ahead=0 behind=0 ab=''
  [ -n "$cwd" ] && st=$(git --no-optional-locks -C "$cwd" status --porcelain=v2 --branch 2>/dev/null)
  while IFS= read -r line; do
    case $line in
      '') ;;
      '# branch.head '*) b=${line#'# branch.head '} ;;
      '# branch.ab '*) read -r _ _ ahead behind <<<"$line"; ahead=${ahead#+}; behind=${behind#-} ;;
      '#'*) ;;
      *) dirty='*' ;;
    esac
  done <<<"$st"
  [ "$b" = '(detached)' ] && b='HEAD'
  if [ -z "$b" ]; then seg "$C_BRANCH" "$(field '.workspace.git_worktree')"; return; fi
  [ "$ahead" -gt 0 ] 2>/dev/null && ab+="↑$ahead"
  [ "$behind" -gt 0 ] 2>/dev/null && ab+="↓$behind"
  printf '%s%s%s' "$(seg "$C_BRANCH" "$b")" "$(seg "$C_DIRTY" "$dirty")" "$(seg "$C_LABEL" "${ab:+ $ab}")"
}

# Claude org from the local login (not in the statusline JSON). Team/Enterprise
# orgs show their name; personal plans (pro, max, ...) show "Personal".
team() {
  jq -r '.oauthAccount
    | if (.organizationName // "") == "" then empty
      elif (.organizationType // "") | test("team|enterprise"; "i") then .organizationName
      else "Personal" end' "$HOME/.claude.json" 2>/dev/null
}

# Rough electricity use of this session, in Wh. Not a measurement: Anthropic
# publishes no energy figures, so this applies public per-token estimates
# (Google/OpenAI disclosures, Epoch AI, TokenPowerBench) to the token counts in
# the session transcript, subagent transcripts included. Treat it as an order
# of magnitude. Cached by total transcript size so an idle refresh doesn't
# re-parse a long session.
energy_wh() {
  local t; t=$(field '.transcript_path')
  [ -f "$t" ] || return
  local files=("$t") f size=0
  while IFS= read -r f; do files+=("$f"); done < <(find "${t%.jsonl}" -name '*.jsonl' 2>/dev/null)
  for f in "${files[@]}"; do size=$(( size + $(wc -c <"$f") )); done

  local sid; sid=$(field '.session_id')
  local cache="${TMPDIR:-/tmp}/statusline-energy-${sid:-x}.txt" csize cwh
  if read -r csize cwh 2>/dev/null <"$cache" && [ "$csize" = "$size" ] && [ -n "$cwh" ]; then
    echo "$cwh"; return
  fi

  # kWh per million tokens for an Opus-class model, including data-centre
  # overhead (PUE). Output (decode) dominates; prefill is far cheaper per token
  # and cache reads skip most of the compute. Smaller models scale down. A
  # streamed response can be logged more than once, so the last entry per
  # message id wins.
  local wh
  wh=$(jq -nR --arg fallback "$(field '.model.id')" '
    def scale: ascii_downcase
      | if test("haiku") then 0.25 elif test("sonnet") then 0.5
        elif test("fable|mythos") then 1.5 else 1 end;
    reduce (inputs | fromjson? | select(.type == "assistant" and (.message.usage | type) == "object")) as $e
      ({}; .[$e.message.id // $e.uuid // ""] = $e.message)
    | [.[] | .usage as $u
        | ( ($u.output_tokens // 0) * 1.0
          + ($u.input_tokens // 0) * 0.2
          + ($u.cache_creation_input_tokens // 0) * 0.25
          + ($u.cache_read_input_tokens // 0) * 0.02 ) / 1000
          * (if (.model // "") == "" then $fallback else .model end | scale)]
    | add // 0' "${files[@]}" 2>/dev/null) || return
  echo "$size $wh" >"$cache" 2>/dev/null
  echo "$wh"
}

# "⚡ ~12 Wh est. (≈0.8 🔋)", the battery being a ~15 Wh smartphone charge.
energy_seg() {
  local wh; wh=$(energy_wh)
  [ -z "$wh" ] && return
  # LC_ALL=C keeps a "." decimal point under locales that use ",".
  local amt phones
  amt=$(LC_ALL=C awk -v w="$wh" 'BEGIN {
    if (w >= 1000) printf "%.2f kWh", w / 1000
    else if (w >= 10) printf "%.0f Wh", w
    else printf "%.1f Wh", w }')
  phones=$(LC_ALL=C awk -v w="$wh" 'BEGIN { printf "%.1f", w / 15 }')
  printf '%s%s' "$(seg "$C_ENERGY" "⚡ ~$amt")" "$(seg "$C_LABEL" " est. (≈$phones 🔋)")"
}

# The weekly limit only shows from 80%, as a "getting close" warning: halfway
# through the week is normal and not worth the space. No reset time, since
# it's the 5h window that stops a session.
weekly_seg() {
  local p; p=$(field '.rate_limits.seven_day.used_percentage')
  [ -n "$p" ] && [ "$(norm_int "$p")" -ge 80 ] && pct_seg '7d' "$p"
}

label_5h=$(until_reset "$(field '.rate_limits.five_hour.resets_at')")
[ -z "$label_5h" ] && label_5h='5h'

parts=(
  "$(shown model  && seg "$C_MODEL" "$(field '.model.display_name')")"
  "$(shown folder && seg "$C_DIR" "$(basename "$cwd" 2>/dev/null)")"
  "$(shown branch && branch_seg)"
  "$(shown 5h     && pct_seg "$label_5h" "$(field '.rate_limits.five_hour.used_percentage')")"
  "$(shown weekly && weekly_seg)"
  "$(shown ctx    && pct_seg 'ctx' "$(field '.context_window.used_percentage')")"
  "$(shown team   && seg "$C_TEAM" "$(team)")"
  "$(shown energy && energy_seg)"
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
