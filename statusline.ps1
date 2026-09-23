# Statusline script (PowerShell)
$ErrorActionPreference = 'SilentlyContinue'
$__input = [Console]::In.ReadToEnd()
try { $j = $__input | ConvertFrom-Json } catch { $j = $null }

# Terminal width for flex-spacer math. STATUSLINE_COLS env var overrides;
# else WindowWidth (throws on redirected stdout / CI), else 80.
$STATUSLINE_COLS = if ($env:STATUSLINE_COLS) {
  try { [int]$env:STATUSLINE_COLS } catch { 80 }
} else {
  try { [Console]::WindowWidth } catch { 80 }
}

# Visible-character length: strip CSI SGR sequences then .Length.
# Wide glyphs (emoji, CJK) count as 1 column - same simplification as the
# interpret backend uses.
function __visibleLen([string]$s) {
  if ([string]::IsNullOrEmpty($s)) { return 0 }
  $stripped = $s -replace "$([char]27)\[[0-9;]*m", ''
  return $stripped.Length
}

function __get($obj, [string]$path) {
  if ($null -eq $obj -or [string]::IsNullOrEmpty($path)) { return '' }
  $cur = $obj
  foreach ($p in $path.Split('.')) {
    if ($null -eq $cur) { return '' }
    $prop = $cur.PSObject.Properties[$p]
    if ($null -eq $prop) { return '' }
    $cur = $prop.Value
  }
  if ($null -eq $cur) { return '' }
  return $cur
}

function __field([string]$path) { [string](__get $j $path) }
function __sgr([string]$codes) {
  if ([string]::IsNullOrEmpty($codes)) { return '' }
  return "$([char]27)[${codes}m"
}
function __reset() { return "$([char]27)[0m" }

# Output sink: when $__SINK is non-null, __emit/__write append to it
# (used for flex-spacer chunk capture). Otherwise bytes go straight to the
# raw standard-output stream as UTF-8.
#
# We deliberately bypass [Console]::Out.Write: that re-encodes through
# [Console]::OutputEncoding, which on Windows PowerShell 5.1 defaults to the
# console's OEM code page (e.g. IBM437 / CP1252). Those code pages can't
# represent the block-bar glyphs, box drawing, or emoji a statusline may emit,
# so they get mangled to '?' regardless of the terminal's own encoding. Writing
# UTF-8 bytes straight to the handle is independent of the console code page AND
# of host color handling. The compiled body below keeps all literals ASCII
# (non-ASCII is emitted as [char] escapes) so the in-memory strings are correct
# even when PowerShell 5.1 parses this BOM-less file as its OEM code page.
$__SINK = $null
$__stdout = [Console]::OpenStandardOutput()
function __write([string]$text) {
  if ($null -eq $script:__SINK) {
    $__b = [System.Text.Encoding]::UTF8.GetBytes($text)
    $script:__stdout.Write($__b, 0, $__b.Length)
  } else { $script:__SINK.Append($text) | Out-Null }
}
function __emit([string]$codes, [string]$text) {
  $out = ''
  if ($codes) { $out += __sgr $codes }
  $out += $text
  if ($codes) { $out += __reset }
  __write $out
}
function __basename([string]$s) {
  if ([string]::IsNullOrEmpty($s)) { return '' }
  $idx = [Math]::Max($s.LastIndexOf('/'), $s.LastIndexOf('\'))
  if ($idx -ge 0) { return $s.Substring($idx + 1) } else { return $s }
}
function __compact([string]$s) {
  if ([string]::IsNullOrEmpty($s)) { return '' }
  $sep = '/'
  if (($s.IndexOf('\') -ge 0) -and ($s.IndexOf('/') -lt 0)) { $sep = '\' }
  $leading = ''
  $body = $s
  if ($s.StartsWith($sep)) { $leading = $sep; $body = $s.Substring(1) }
  if ($body -eq '') { return $leading }
  $parts = $body -split [regex]::Escape($sep)
  if ($parts.Length -le 1) { return $s }
  $last = $parts[$parts.Length - 1]
  $collapsed = New-Object System.Collections.Generic.List[string]
  for ($i = 0; $i -lt $parts.Length - 1; $i++) {
    $seg = $parts[$i]
    if ([string]::IsNullOrEmpty($seg)) { $collapsed.Add('') }
    else { $collapsed.Add($seg.Substring(0, 1)) }
  }
  $collapsed.Add($last)
  return $leading + ($collapsed -join $sep)
}
function __tildify([string]$s) {
  if ([string]::IsNullOrEmpty($s)) { return '' }
  $h = $env:USERPROFILE
  if (-not $h) { $h = $env:HOME }
  if ($h -and $s.StartsWith($h)) { return '~' + $s.Substring($h.Length) }
  return $s
}
function __truncate([string]$s, [int]$n) {
  if ($n -le 0 -or $s.Length -le $n) { return $s }
  if ($n -le 1) { return $s.Substring(0, $n) }
  return $s.Substring(0, $n - 1) + [char]0x2026
}
function __costFmt([string]$v, [int]$prec) {
  $n = 0.0
  [double]::TryParse($v, [ref]$n) | Out-Null
  return '$' + $n.ToString('F' + $prec)
}
function __durHms([string]$v) {
  $ms = 0; [int64]::TryParse($v, [ref]$ms) | Out-Null
  $total = [int]([math]::Floor($ms / 1000))
  # [int] casts are load-bearing: "D2" is integer-only and throws on the double
  # that [math]::Floor returns. Only the $h branch below hit it - the other one
  # applies D2 to $s, which was already an int.
  $h = [int][math]::Floor($total / 3600)
  $m = [int][math]::Floor(($total % 3600) / 60)
  $s = [int]($total % 60)
  if ($h -gt 0) { return ('{0}:{1:D2}:{2:D2}' -f $h, $m, $s) }
  return ('{0}:{1:D2}' -f $m, $s)
}
function __durHuman([string]$v) {
  $ms = 0; [int64]::TryParse($v, [ref]$ms) | Out-Null
  $total = [int]([math]::Floor($ms / 1000))
  if ($total -lt 60) { return ('{0}s' -f $total) }
  $m = [math]::Floor($total / 60); $s = $total % 60
  if ($m -lt 60) { if ($s -gt 0) { return ('{0}m {1}s' -f $m, $s) } else { return ('{0}m' -f $m) } }
  $h = [math]::Floor($m / 60); $mm = $m % 60
  if ($mm -gt 0) { return ('{0}h {1}m' -f $h, $mm) } else { return ('{0}h' -f $h) }
}
function __bar([string]$v, [int]$width, [string]$filled, [string]$empty) {
  $p = 0.0; [double]::TryParse($v, [ref]$p) | Out-Null
  if ($p -lt 0) { $p = 0 } elseif ($p -gt 100) { $p = 100 }
  $n = [int][math]::Round(($p * $width) / 100)
  $e = $width - $n
  return ($filled * $n) + ($empty * $e)
}
function __normInt([string]$v) {
  if ([string]::IsNullOrEmpty($v)) { return 0 }
  $idx = $v.IndexOf('.')
  if ($idx -ge 0) { $v = $v.Substring(0, $idx) }
  $n = 0
  if (-not [int64]::TryParse($v, [ref]$n)) { return 0 }
  if ($n -lt 0) { return 0 }
  return $n
}
function __fmtTokenCompact([string]$v) {
  $n = __normInt $v
  if ($n -lt 1000) { return [string]$n }
  if ($n -lt 1000000) {
    $whole = [math]::Floor($n / 1000)
    $rem = $n - ($whole * 1000)
    $dec = [math]::Floor($rem / 100)
    if ($dec -eq 0) { return ('{0}k' -f $whole) }
    return ('{0}.{1}k' -f $whole, $dec)
  }
  $whole = [math]::Floor($n / 1000000)
  $rem = $n - ($whole * 1000000)
  $dec = [math]::Floor($rem / 100000)
  if ($dec -eq 0) { return ('{0}M' -f $whole) }
  return ('{0}.{1}M' -f $whole, $dec)
}
function __fmtTokenFull([string]$v) {
  $n = __normInt $v
  return $n.ToString('N0', [System.Globalization.CultureInfo]::InvariantCulture)
}
function __tokensUsed() { __field 'context_window.total_input_tokens' }
function __tokensTotal() { __field 'context_window.context_window_size' }
function __tokensRemaining() {
  $u = __normInt (__tokensUsed)
  $t = __normInt (__tokensTotal)
  $r = $t - $u
  if ($r -lt 0) { $r = 0 }
  return [string]$r
}
function __tokensPctInt() {
  $p = __field 'context_window.used_percentage'
  return [string](__normInt $p)
}
function __gitBranch() {
  $cwd = __field 'workspace.current_dir'
  if (-not $cwd) { $cwd = __field 'cwd' }
  if ($cwd -and (Get-Command git -ErrorAction SilentlyContinue)) {
    $b = & git -C "$cwd" rev-parse --abbrev-ref HEAD 2>$null
    if ($b) { return $b.Trim() }
  }
  return __field 'workspace.git_worktree'
}
function __gitDirty() {
  $cwd = __field 'workspace.current_dir'
  if (-not $cwd) { $cwd = __field 'cwd' }
  if ($cwd -and (Get-Command git -ErrorAction SilentlyContinue)) {
    $s = & git -C "$cwd" status --porcelain 2>$null
    if ($s) { return '1' }
  }
  return '0'
}
function __tick() {
  if ($env:STATUSLINE_CLOCK_OVERRIDE) {
    $o = 0
    if ([int64]::TryParse($env:STATUSLINE_CLOCK_OVERRIDE, [ref]$o)) { return $o }
  }
  return [DateTimeOffset]::Now.ToUnixTimeSeconds()
}
function __relTime([string]$v) {
  if ([string]::IsNullOrEmpty($v)) { return '' }
  $target = 0.0
  if (-not [double]::TryParse($v, [ref]$target)) { return '' }
  $now = __tick
  $diff = [int]([math]::Floor($target - $now))
  if ($diff -le 0) { return '' }
  if ($diff -lt 60) { return ('T-{0}s' -f $diff) }
  # [int] casts as in __durHms: "D2" is integer-only and throws on a double.
  if ($diff -lt 3600) {
    $m = [int][math]::Floor($diff / 60); $s = [int]($diff % 60)
    return ('T-{0}m{1:D2}s' -f $m, $s)
  }
  $h = [int][math]::Floor($diff / 3600); $rem = [int][math]::Floor(($diff % 3600) / 60)
  return ('T-{0}h{1:D2}m' -f $h, $rem)
}

# Bare compact countdown to a unix-epoch-seconds target: "2h14m", "14m", "<1m".
# __relTime does the same arithmetic but prefixes "T-", which reads as a launch
# clock; this one is used as a LABEL, so it stays bare. Returns '' when the
# target is absent, unparseable, or already past, letting the caller fall back.
#
# The floors are cast to [int] before formatting: PowerShell division promotes
# to double, [math]::Floor keeps it double, and the "D2" format specifier is
# integer-only - it throws on a double.
function __untilReset([string]$v) {
  if ([string]::IsNullOrEmpty($v)) { return '' }
  $target = 0.0
  if (-not [double]::TryParse($v, [ref]$target)) { return '' }
  $diff = [int]([math]::Floor($target - (__tick)))
  if ($diff -le 0) { return '' }
  $h = [int][math]::Floor($diff / 3600)
  $m = [int][math]::Floor(($diff % 3600) / 60)
  if ($h -gt 0) { return ('{0}h{1:D2}m' -f $h, $m) }
  if ($m -gt 0) { return ('{0}m' -f $m) }
  return '<1m'
}

# ---- palette --------------------------------------------------------------
# 256-colour codes, not truecolour: every terminal that runs Claude Code
# handles these. NO_COLOR (the de-facto standard) blanks every code, and __seg
# then emits bare text with no SGR bytes at all.
$__NOCOLOR = [bool]$env:NO_COLOR
function __c([string]$codes) { if ($__NOCOLOR) { return '' } else { return $codes } }

$C_MODEL  = __c '38;5;80'   # turquoise - the identity anchor
$C_DIR    = __c '38;5;252'  # near-white
$C_BRANCH = __c '38;5;108'  # muted git green
$C_SEP    = __c '38;5;240'  # dark grey, recedes
$C_LABEL  = __c '38;5;244'  # grey, quieter than the number it labels

# Used-percentage ramp: turquoise while healthy, warming to red at the wall.
# Thresholds read as USED, so for both figures higher is worse.
function __pctColor([int]$p) {
  if ($p -ge 90) { return (__c '1;38;5;196') }  # bold red
  if ($p -ge 80) { return (__c '38;5;208') }    # orange
  if ($p -ge 60) { return (__c '38;5;220') }    # yellow
  return (__c '38;5;79')                        # turquoise-green
}

# A coloured segment, or '' for empty text so the joiner can drop it rather
# than leave a doubled separator behind.
function __seg([string]$codes, [string]$text) {
  if ([string]::IsNullOrEmpty($text)) { return '' }
  if ([string]::IsNullOrEmpty($codes)) { return $text }
  return (__sgr $codes) + $text + (__reset)
}

# Grey label plus threshold-coloured number, e.g. "5h 37%". __normInt truncates,
# so a float field renders as "37%" rather than "37.482352%".
function __pctSeg([string]$label, [string]$raw) {
  if ([string]::IsNullOrEmpty($raw)) { return '' }
  $n = __normInt $raw
  return (__seg $C_LABEL ($label + ' ')) + (__seg (__pctColor $n) ("$n" + '%'))
}

# Label the 5-hour figure with how long until the window resets rather than the
# window's length. Falls back to the static "5h" when resets_at is absent or
# already past: rate_limits appears only for Pro/Max after the first API
# response, and each window can be absent independently.
$__5h = __untilReset (__field 'rate_limits.five_hour.resets_at')
if (-not $__5h) { $__5h = '5h' }

$__parts = New-Object System.Collections.Generic.List[string]
foreach ($__p in @(
  (__seg $C_MODEL  (__field 'model.display_name')),
  (__seg $C_DIR    (__basename (__field 'workspace.current_dir'))),
  (__seg $C_BRANCH (__gitBranch)),
  (__pctSeg $__5h (__field 'rate_limits.five_hour.used_percentage')),
  (__pctSeg 'ctx' (__field 'context_window.used_percentage'))
)) { if ($__p) { $__parts.Add($__p) } }

__write ($__parts -join (__seg $C_SEP ' | '))

# A blank row underneath, so the permission prompt is not pressed against the
# line. Claude Code renders each output line as its own row.
#
# The spacer is a ZERO WIDTH SPACE (U+200B), not an empty line and not a plain
# space - both of those were trimmed away and produced no row. U+200B is
# category Cf, not Zs, so it is not in the ECMAScript WhiteSpace set and
# survives a trim() while still rendering as nothing. It carries no SGR codes
# either: the docs warn that multi-line output with escape sequences is likelier
# to glitch, and this row has nothing to colour.
__write ("`n" + [char]0x200B)

$__stdout.Flush()
exit 0
