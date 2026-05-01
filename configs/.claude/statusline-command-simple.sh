#!/usr/bin/env bash
# Claude Code status line — mirrors custom-theme.zsh-theme style

input=$(cat)

cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')
model=$(echo "$input" | jq -r '.model.display_name // ""')
remaining=$(echo "$input" | jq -r '.context_window.remaining_percentage // empty')

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

# Context used (100 - remaining)
ctx_part=""
if [ -n "$remaining" ]; then
  used=$(awk -v r="$remaining" 'BEGIN { printf "%.0f", 100 - r }')
  ctx_part=" ctx:${used}%"
fi

# 5-hour session quota used percentage (matches /usage output)
# Optionally append reset time when resets_at epoch is available (BSD date -r on macOS)
session_part=""
if [ -n "$five_hour_pct" ]; then
  reset_str=""
  if [ -n "$five_hour_resets_at" ]; then
    # BSD date: -r <epoch> converts epoch seconds to local time
    # Strip leading zero from hour and lowercase am/pm for compact display (e.g. 5:30pm)
    reset_time=$(date -r "$five_hour_resets_at" +%I:%M%p 2>/dev/null | sed 's/^0//;s/AM/am/;s/PM/pm/')
    # Elapsed % of the 5-hour (18000s) window — same value used in pace calc
    now=$(date +%s)
    elapsed=$((18000 - (five_hour_resets_at - now)))
    time_pct_int=0
    if [ "$elapsed" -gt 0 ] && [ "$elapsed" -le 18000 ]; then
      time_pct_int=$(awk -v e="$elapsed" 'BEGIN { printf "%.0f", (e/18000)*100 }')
    fi
    reset_str=" (${time_pct_int}% → ${reset_time})"
  fi
  pct_int=$(printf '%.0f' "$five_hour_pct")
  # Color thresholds: <50 dim, 50-74 yellow, 75-89 orange (256-color 208), 90+ red
  session_color=""
  if [ "$pct_int" -ge 90 ]; then
    session_color="31"
  elif [ "$pct_int" -ge 75 ]; then
    session_color="38;5;208"
  elif [ "$pct_int" -ge 50 ]; then
    session_color="33"
  fi
  if [ -n "$session_color" ]; then
    session_part=$' \033['"${session_color}"$'msess:'"${pct_int}"$'%\033[0m\033[2m'"${reset_str}"
  else
    session_part=" sess:${pct_int}%${reset_str}"
  fi
fi

# Pace: usage% minus time%, in percentage points. +N = ahead of pace, -N = behind.
# 5-hour window is 18000s; elapsed = 18000 - (resets_at - now).
pace_part=""
if [ -n "$five_hour_pct" ] && [ -n "$five_hour_resets_at" ]; then
  now=$(date +%s)
  elapsed=$((18000 - (five_hour_resets_at - now)))
  if [ "$elapsed" -gt 0 ] && [ "$elapsed" -le 18000 ]; then
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
    pace_part=$' \033[22;'"${color}"$'mpace:'"${delta}"$'pp\033[0m\033[2m'
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
      etr_dur="${etr_h}h ${etr_m}m"
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
# dim for model/context/session; pace gets its own color
printf "\033[94m%s\033[0m  \033[36m%s\033[0m%s\n\033[2m%s%s%s%s%s\033[0m" \
  "$cwd_display" \
  "$git_branch" \
  "$wt_part" \
  "$model" \
  "$ctx_part" \
  "$session_part" \
  "$pace_part" \
  "$etr_part"
