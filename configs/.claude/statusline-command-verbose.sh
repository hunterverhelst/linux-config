#!/usr/bin/env bash
# Claude Code status line — multi-row working status.
# Field reference: https://code.claude.com/docs/en/statusline

input=$(cat)

cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')
model=$(echo "$input" | jq -r '.model.display_name // ""')
# Normalize the trailing extended-context qualifier across Anthropic display
# name variants to a compact " (<size>)" suffix:
#   "Opus 4.7 (1M context)"  -> "Opus 4.7 (1M)"
#   "Opus 4.7, 1M context"   -> "Opus 4.7 (1M)"
#   "Opus 4.7 1M context"    -> "Opus 4.7 (1M)"
# A leading char class consumes any combination of whitespace, comma, or
# opening paren before the size token.
model=$(printf '%s' "$model" | sed -E 's/[[:space:],(]+([0-9]+[KMGkmg])[[:space:]]+[Cc]ontext\)?[[:space:]]*$/ (\1)/')
remaining=$(echo "$input" | jq -r '.context_window.remaining_percentage // empty')

# Current local time (e.g. 5:30pm), prefixed to the second line of the
# working status. Lowercase am/pm and strip the leading hour zero for
# consistency with the session-quota reset-time formatting below.
time_part="[$(date +%I:%M%p | sed 's/^0//;s/AM/am/;s/PM/pm/')] "

# 5-hour rolling session quota (same value shown by /usage)
five_hour_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
five_hour_resets_at=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')

# Git branch (skip optional locks).
# When a Claude-managed worktree session is active (--worktree or
# EnterWorktree), the worktree branch is auto-named `worktree-<wt-name>`,
# which is fully redundant with the [wt:...] marker shown on the same line.
# Suppress the (branch) segment in that case to reclaim ~38 chars on line 1.
# Skipping git here also avoids the subprocess work entirely.
git_branch=""
wt_name_active=$(echo "$input" | jq -r '.worktree.name // empty')
if [ -z "$wt_name_active" ] && git -C "$cwd" rev-parse --git-dir > /dev/null 2>&1; then
  branch=$(GIT_OPTIONAL_LOCKS=0 git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null || GIT_OPTIONAL_LOCKS=0 git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
  if [ -n "$branch" ]; then
    dirty=""
    if ! GIT_OPTIONAL_LOCKS=0 git -C "$cwd" diff --quiet 2>/dev/null || ! GIT_OPTIONAL_LOCKS=0 git -C "$cwd" diff --cached --quiet 2>/dev/null; then
      dirty="*"
    fi
    git_branch="($branch$dirty)  "
  fi
fi

# Context used (100 - remaining). Threshold colors flag pressure on the
# current conversation's context window: yellow at >=50% (start watching),
# red at >=70% (compaction/handoff territory).
ctx_part=""
if [ -n "$remaining" ]; then
  used=$(awk -v r="$remaining" 'BEGIN { printf "%.0f", 100 - r }')
  ctx_color=""
  if [ "$used" -ge 70 ]; then
    ctx_color="31"
  elif [ "$used" -ge 50 ]; then
    ctx_color="33"
  fi
  if [ -n "$ctx_color" ]; then
    # Only red gets bright (22 = normal intensity, overrides row's dim).
    # Yellow inherits the row's dim attribute so it tints without grabbing
    # the eye — red is the only "alarm" state.
    if [ "$ctx_color" = "31" ]; then
      ctx_part=$' \033[22;31mctx:'"${used}"$'%\033[0m\033[2m'
    else
      ctx_part=$' \033['"${ctx_color}"$'mctx:'"${used}"$'%\033[0m\033[2m'
    fi
  else
    ctx_part=" ctx:${used}%"
  fi
fi

# Token formatter — shared by both the conversation-cumulative tokens
# (tok_part) and the last-prompt counts (last_prompt_part). Empty input
# renders as "—". Compacts to "Xk" / "X.YYM" so even multi-million-token
# sessions stay readable.
fmt_tok() {
  awk -v n="$1" 'BEGIN {
    if (n == "") { print "—"; exit }
    if (n < 1000) printf "%d", n
    else if (n < 1000000) printf "%.1fk", n/1000
    else printf "%.2fM", n/1000000
  }'
}

# Cumulative session token totals — ↓ for input, ↑ for output.
# These are session-long sums (context_window.total_input_tokens /
# total_output_tokens), distinct from the ctx% gauge which reflects the
# current context window state from the last API call.
tok_part=""
ctx_in_top=$(echo "$input" | jq -r '.context_window.total_input_tokens // empty')
ctx_out_top=$(echo "$input" | jq -r '.context_window.total_output_tokens // empty')
if [ -n "$ctx_in_top" ] || [ -n "$ctx_out_top" ]; then
  in_str=$(fmt_tok "$ctx_in_top")
  out_str=$(fmt_tok "$ctx_out_top")
  tok_part=" (↓${in_str} ↑${out_str})"
fi

# Last-prompt token cluster — token counts from the most recent API call
# (context_window.current_usage.*). Distinct from tok_part which sums the
# whole conversation. Hidden before the first API call: current_usage is
# null, so all sub-fields render as empty and the cluster is suppressed.
cu_in_top=$(echo "$input" | jq -r '.context_window.current_usage.input_tokens // empty')
cu_out_top=$(echo "$input" | jq -r '.context_window.current_usage.output_tokens // empty')
cu_cw_top=$(echo "$input" | jq -r '.context_window.current_usage.cache_creation_input_tokens // empty')
cu_cr_top=$(echo "$input" | jq -r '.context_window.current_usage.cache_read_input_tokens // empty')
last_prompt_part=""
if [ -n "$cu_in_top" ] || [ -n "$cu_out_top" ] || [ -n "$cu_cw_top" ] || [ -n "$cu_cr_top" ]; then
  last_prompt_part=" ↓$(fmt_tok "$cu_in_top") ↑$(fmt_tok "$cu_out_top") cr:$(fmt_tok "$cu_cr_top") cw:$(fmt_tok "$cu_cw_top")"
  # Cluster separator: │ between the model/effort anchor and the
  # last-prompt token cluster on row 2.
  last_prompt_part=" │$last_prompt_part"
fi

# Shared 5-hour window timing: now / elapsed / elapsed%. The 5h window is
# 18000s; elapsed = 18000 - (resets_at - now). Hoisted so both session_part
# (5h: usage%/elapsed%) and pace_part can read the same values.
now=$(date +%s)
elapsed=""
time_pct_int=""
if [ -n "$five_hour_resets_at" ]; then
  elapsed=$((18000 - (five_hour_resets_at - now)))
  if [ "$elapsed" -gt 0 ] && [ "$elapsed" -le 18000 ]; then
    time_pct_int=$(awk -v e="$elapsed" 'BEGIN { printf "%.0f", (e/18000)*100 }')
  fi
fi

# 5-hour session quota used percentage (matches /usage output), paired with
# the elapsed% of the 5h window separated by a slash: `5h:62%/40%`.
# usage% > elapsed% = burning faster than wall-clock; pace shows the delta.
session_part=""
if [ -n "$five_hour_pct" ]; then
  pct_int=$(printf '%.0f' "$five_hour_pct")
  if [ -n "$time_pct_int" ]; then
    session_part=" 5h:${pct_int}%/${time_pct_int}%"
  else
    session_part=" 5h:${pct_int}%"
  fi
fi

# Reset time for the 5-hour window — its own row-3 cluster.
# BSD date: -r <epoch> converts epoch seconds to local time. Strip leading
# zero from hour and lowercase am/pm to match the row-2 [time] formatting.
reset_part=""
if [ -n "$five_hour_resets_at" ]; then
  reset_time=$(date -r "$five_hour_resets_at" +%I:%M%p 2>/dev/null | sed 's/^0//;s/AM/am/;s/PM/pm/')
  reset_part=" →${reset_time}"
fi

# Pace: usage% minus elapsed%, in percentage points. +N = ahead of pace,
# -N = behind. Renders as `(+5)` next to 5h:; the parentheses stay in the
# row's dim wrap and only the number is tinted.
pace_part=""
if [ -n "$five_hour_pct" ] && [ -n "$elapsed" ] && [ "$elapsed" -gt 0 ] && [ "$elapsed" -le 18000 ]; then
  read -r delta color <<EOF
$(awk -v used="$five_hour_pct" -v elapsed="$elapsed" 'BEGIN {
  time_pct = (elapsed / 18000) * 100
  d = used - time_pct
  # yellow if >=+10pp ahead, red if >=+25pp, green if <=-10pp behind, else dim
  if (d >= 25) c = "31"
  else if (d >= 10) c = "33"
  else if (d <= -10) c = "32"
  else c = "2"
  printf "%+d %s", int(d + (d>=0?0.5:-0.5)), c
}')
EOF
  # Only red gets bright (22 = normal intensity, overrides row's dim).
  # Yellow/green/default inherit the surrounding row's dim attribute, so
  # they tint without grabbing the eye — red is the only "alarm" state.
  # Parens live outside the color SGR so they stay in row dim, not tinted.
  if [ "$color" = "31" ]; then
    pace_part=$' (\033[22;31m'"${delta}"$'\033[0m\033[2m)'
  else
    pace_part=$' (\033['"${color}"$'m'"${delta}"$'\033[0m\033[2m)'
  fi
fi

# ETR (estimated time remaining): duration until session is projected to hit 100% at the current rate,
# followed by the wall-clock time in parentheses. Only shown when pace is red (>=+25pp).
# rate = used%/elapsed; sec_to_100 = (100-used)*elapsed/used.
etr_part=""
if [ "$color" = "31" ] && [ -n "$elapsed" ] && [ "$elapsed" -gt 0 ]; then
  etr_secs=$(awk -v used="$five_hour_pct" -v elapsed="$elapsed" 'BEGIN {
    if (used <= 0) exit
    printf "%d", (100 - used) * elapsed / used
  }')
  if [ -n "$etr_secs" ] && [ "$etr_secs" -gt 0 ]; then
    etr_h=$((etr_secs / 3600))
    etr_m=$(((etr_secs % 3600) / 60))
    if [ "$etr_h" -gt 0 ]; then
      etr_dur="${etr_h}h${etr_m}m"
    else
      etr_dur="${etr_m}m"
    fi
    etr_time=$(date -r $((now + etr_secs)) +%I:%M%p 2>/dev/null | sed 's/^0//;s/AM/am/;s/PM/pm/')
    etr_part=$' \033[22;31mETR:'"${etr_dur}"$' ('"${etr_time}"$')\033[0m\033[2m'
  fi
fi

# Tilde-ify home directory for a compact cwd display
cwd_display="$cwd"
if [ -n "$HOME" ] && [ "${cwd#"$HOME"}" != "$cwd" ]; then
  cwd_display="~${cwd#"$HOME"}"
fi

# Collapse `/.claude/worktrees/<name>` from the displayed path. When you're
# inside a Claude-managed worktree the magenta [wt:<name>] marker already
# carries the worktree name, so duplicating it in the cwd is just stealing
# horizontal space — and these paths blow past terminal width fast.
# Works whether cwd is the worktree root or somewhere deeper inside it:
#   ~/repo/.claude/worktrees/feat        -> ~/repo
#   ~/repo/.claude/worktrees/feat/src/x  -> ~/repo/src/x
cwd_display=$(printf '%s' "$cwd_display" | sed -E 's|/\.claude/worktrees/[^/]+||')

# Worktree marker (magenta) — surfaces both kinds of worktree presence:
#   - .worktree.name (Claude-managed, from --worktree or EnterWorktree); when
#     present, also show the original branch we'd return to on exit
#   - .workspace.git_worktree (any linked worktree the cwd happens to be in)
# Marker shape: [wt:name] or [wt:name ← original_branch]
wt_name_top=$(echo "$input" | jq -r '.worktree.name // empty')
wt_orig_branch_top=$(echo "$input" | jq -r '.worktree.original_branch // empty')
ws_git_worktree_top=$(echo "$input" | jq -r '.workspace.git_worktree // empty')
wt_part=""
if [ -n "$wt_name_top" ]; then
  if [ -n "$wt_orig_branch_top" ]; then
    wt_part=$'\033[35m[wt:'"$wt_name_top"$' ← '"$wt_orig_branch_top"$']\033[0m'
  else
    wt_part=$'\033[35m[wt:'"$wt_name_top"$']\033[0m'
  fi
elif [ -n "$ws_git_worktree_top" ]; then
  wt_part=$'\033[35m[wt:'"$ws_git_worktree_top"$']\033[0m'
fi

# Build output with ANSI colors matching the theme:
# Blue for cwd, cyan for git branch, magenta for worktree marker,
# dim for model/context/session; pace gets its own color.
# Effort level (low/medium/high/xhigh/max) — appended right after the model
# name on line 2. Absent for models that don't support the parameter.
effort_top=$(echo "$input" | jq -r '.effort.level // empty')
effort_part=""
if [ -n "$effort_top" ]; then
  effort_part=" eff:${effort_top}"
fi

# Cost cluster — sits at the tail of row 2 (this-conversation info). The
# cost.total_* fields are scoped to the current session_id (this chat),
# NOT the 5-hour rate-limit window — see code.claude.com/docs/en/statusline:
# "Estimated session cost in USD" / "Total wall-clock time since the session
# started". Each component (cost, wall, api) is included only if its source
# field is present, so partial data renders cleanly. Durations format as
# Xh Ym when the wall clock crosses an hour.
cost_usd_top=$(echo "$input" | jq -r '.cost.total_cost_usd // empty')
cost_dur_top=$(echo "$input" | jq -r '.cost.total_duration_ms // empty')
cost_api_top=$(echo "$input" | jq -r '.cost.total_api_duration_ms // empty')
fmt_ms_inline() {
  awk -v ms="$1" 'BEGIN {
    s = int(ms/1000)
    h = int(s/3600); s = s % 3600
    m = int(s/60); s = s % 60
    if (h > 0) {
      if (m > 0) printf "%dh%dm", h, m; else printf "%dh", h
    } else if (m > 0) {
      if (s > 0) printf "%dm%ds", m, s; else printf "%dm", m
    } else {
      printf "%ds", s
    }
  }'
}
cost_inline=""
if [ -n "$cost_usd_top" ]; then
  cost_inline+=" \$$(awk -v v="$cost_usd_top" 'BEGIN { printf "%.4f", v }')"
fi
# Combined wall + api duration: <wall> (<api>). Wall is the headline figure
# (continuous since session start); api in parens is the subset spent in
# generation. Parens visually subordinate api as a refinement of wall.
if [ -n "$cost_dur_top" ] && [ -n "$cost_api_top" ]; then
  cost_inline+=" $(fmt_ms_inline "$cost_dur_top") ($(fmt_ms_inline "$cost_api_top"))"
elif [ -n "$cost_dur_top" ]; then
  cost_inline+=" $(fmt_ms_inline "$cost_dur_top")"
elif [ -n "$cost_api_top" ]; then
  cost_inline+=" $(fmt_ms_inline "$cost_api_top")"
fi
# Cluster separator: │ between the context-info cluster and the cost
# cluster on row 3.
[ -n "$cost_inline" ] && cost_inline=" │$cost_inline"

# Four-row working status:
#   Row 1: filesystem location  — cwd + git branch + worktree marker
#   Row 2: last prompt          — time + model + current_usage tokens
#   Row 3: this conversation    — effort + ctx% + ∑tokens + cost
#   Row 4: 5-hour session window — quota + pace + ETR (when red) + reset
# Each row beyond the first is wrapped in its own dim SGR block.

# Row 1: filesystem (no leading newline — this is the first output)
printf "\033[94m%s\033[0m  \033[36m%s\033[0m%s" \
  "$cwd_display" \
  "$git_branch" \
  "$wt_part"

# Row 2: last prompt — time + model + effort anchor + current_usage cluster.
# Effort lives here because it parameterizes the most-recent API call right
# alongside the model. When current_usage is null (pre-first-API-call)
# last_prompt_part is empty, leaving just the time/model/effort anchor.
printf "\n\033[2m%s%s%s%s\033[0m" \
  "$time_part" \
  "$model" \
  "$effort_part" \
  "$last_prompt_part"

# Row 3: this conversation + 5h window joined by a heavy bold ┃.
# Cluster hierarchy: │ = light separator within a logical group;
# ┃ (bold) = boundary between the conversation cluster and the 5h cluster
# — the visual break that used to be a newline. Trim the single leading
# space from each side so the row left-aligns flush with rows 1 and 2.
row3="${ctx_part}${tok_part}${cost_inline}"
row3="${row3# }"
row4="${session_part}${reset_part}${pace_part}${etr_part}"
row4="${row4# }"
sep_bold=" ┃ "
if [ -n "$row3" ] && [ -n "$row4" ]; then
  printf "\n\033[2m%s%s%s\033[0m" "$row3" "$sep_bold" "$row4"
elif [ -n "$row3" ]; then
  printf "\n\033[2m%s\033[0m" "$row3"
elif [ -n "$row4" ]; then
  printf "\n\033[2m%s\033[0m" "$row4"
fi
