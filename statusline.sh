#!/bin/bash
# Line 1: Model | tokens used/total % used | thinking: on/off | effort | <duration>
# Line 2: current: <progressbar> % (<reset>) | weekly: <progressbar> % (<reset>) | extra: <progressbar> $used/$limit (<reset>) | cost: $X.XX
# Line 3: <projectdir> | <repo owner/name> (<worktree>)

set -f  # disable globbing

input=$(cat)

if [ -z "$input" ]; then
    printf "Claude"
    exit 0
fi

# ANSI colors matching oh-my-posh theme
blue='\033[38;2;0;153;255m'
orange='\033[38;2;255;176;85m'
green='\033[38;2;0;160;0m'
cyan='\033[38;2;46;149;153m'
red='\033[38;2;255;85;85m'
yellow='\033[38;2;230;200;0m'
white='\033[38;2;220;220;220m'
dim='\033[2m'
reset='\033[0m'

# Format token counts (e.g., 50k / 200k)
format_tokens() {
    local num=$1
    if [ "$num" -ge 1000000 ]; then
        awk "BEGIN {printf \"%.1fm\", $num / 1000000}"
    elif [ "$num" -ge 1000 ]; then
        awk "BEGIN {printf \"%.0fk\", $num / 1000}"
    else
        printf "%d" "$num"
    fi
}

# Format milliseconds to compact duration (e.g. 1h 23m, 45m 12s, 12s)
format_duration() {
    local ms=$1
    local total_s=$(( ms / 1000 ))
    local h=$(( total_s / 3600 ))
    local m=$(( (total_s % 3600) / 60 ))
    local s=$(( total_s % 60 ))
    if [ "$h" -gt 0 ]; then
        printf "%dh %dm" "$h" "$m"
    elif [ "$m" -gt 0 ]; then
        printf "%dm %ds" "$m" "$s"
    else
        printf "%ds" "$s"
    fi
}

# Build a colored progress bar
# Usage: build_bar <pct> <width>
build_bar() {
    local pct=$1
    local width=$2
    [ "$pct" -lt 0 ] 2>/dev/null && pct=0
    [ "$pct" -gt 100 ] 2>/dev/null && pct=100

    # Round to nearest cell, but show at least one cell for any non-zero usage
    # (with only 7 cells, each is ~14%, so flooring hides low percentages).
    local filled=$(( (pct * width + 50) / 100 ))
    [ "$filled" -eq 0 ] && [ "$pct" -gt 0 ] && filled=1
    [ "$filled" -gt "$width" ] && filled=$width
    local empty=$(( width - filled ))

    # Color based on usage level
    local bar_color
    if [ "$pct" -ge 90 ]; then bar_color="$red"
    elif [ "$pct" -ge 70 ]; then bar_color="$yellow"
    elif [ "$pct" -ge 50 ]; then bar_color="$orange"
    else bar_color="$green"
    fi

    # Trailing space after each cell gives the reference "spaced segment" look.
    # Visible width of the returned bar is therefore 2 * width.
    local filled_str="" empty_str=""
    for ((i=0; i<filled; i++)); do filled_str+="▰ "; done
    for ((i=0; i<empty; i++)); do empty_str+="▱ "; done

    printf "${bar_color}${filled_str}${dim}${empty_str}${reset}"
}

# ===== Extract data from JSON =====
model_name=$(echo "$input" | jq -r '.model.display_name // "Claude"')

# Claude Code version — used in the usage-API User-Agent
cc_version=$(echo "$input" | jq -r '.version // "unknown"')

# Context window
size=$(echo "$input" | jq -r '.context_window.context_window_size // 200000')
[ "$size" -eq 0 ] 2>/dev/null && size=200000

# Token usage — tokens currently in the context window (input includes cache reads/writes)
total_input=$(echo "$input" | jq -r '.context_window.total_input_tokens // 0')
total_output=$(echo "$input" | jq -r '.context_window.total_output_tokens // 0')
current=$(( total_input + total_output ))

used_tokens=$(format_tokens $current)
total_tokens=$(format_tokens $size)

# Percent of context used — pre-calculated by Claude Code, no local math
pct_used=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | awk '{printf "%.0f", $1}')

# Check thinking status — live session value from the stdin JSON
thinking_on=false
thinking_val=$(echo "$input" | jq -r '.thinking.enabled // false')
[ "$thinking_val" = "true" ] && thinking_on=true

# Reasoning effort — absent when the current model doesn't support it
effort_level=$(echo "$input" | jq -r '.effort.level // empty')

# Session wall-clock time — shown at the end of line 1
duration_ms=$(echo "$input" | jq -r '.cost.total_duration_ms // 0')

# ===== LINE 1: Model | tokens % | thinking | effort | session time =====
line1=""
line1+="${blue}${model_name}${reset}"
line1+=" ${dim}|${reset} "
line1+="${orange}${used_tokens} / ${total_tokens}${reset}"
line1+=" "
line1+="${green}${pct_used}%${reset}"
line1+=" ${dim}|${reset} "
line1+="thinking: "
if $thinking_on; then
    line1+="${orange}On${reset}"
else
    line1+="${dim}Off${reset}"
fi
if [ -n "$effort_level" ]; then
    line1+=" ${dim}|${reset} "
    line1+="effort: ${orange}${effort_level}${reset}"
fi
if [ "$duration_ms" -gt 0 ] 2>/dev/null; then
    line1+=" ${dim}|${reset} "
    line1+="${dim}⏱${reset} ${white}$(format_duration $duration_ms)${reset}"
fi

# ===== CONTEXT LINE: project dir | repo owner/name (worktree) =====
project_dir=$(echo "$input" | jq -r '.workspace.project_dir // empty')
repo_owner=$(echo "$input" | jq -r '.workspace.repo.owner // empty')
repo_name=$(echo "$input" | jq -r '.workspace.repo.name // empty')
worktree=$(echo "$input" | jq -r '.workspace.git_worktree // empty')
total_cost=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')

line_ctx=""
if [ -n "$project_dir" ]; then
    line_ctx+="${cyan}${project_dir##*/}${reset}"
fi
if [ -n "$repo_name" ]; then
    [ -n "$line_ctx" ] && line_ctx+=" ${dim}|${reset} "
    if [ -n "$repo_owner" ]; then
        line_ctx+="${dim}⎇${reset} ${white}${repo_owner}/${repo_name}${reset}"
    else
        line_ctx+="${dim}⎇${reset} ${white}${repo_name}${reset}"
    fi
fi
if [ -n "$worktree" ]; then
    line_ctx+=" ${orange}(${worktree})${reset}"
fi

# ===== Cross-platform OAuth token resolution (from statusline.sh) =====
# Tries credential sources in order: env var → macOS Keychain → Linux creds file → GNOME Keyring
get_oauth_token() {
    local token=""

    # 1. Explicit env var override
    if [ -n "$CLAUDE_CODE_OAUTH_TOKEN" ]; then
        echo "$CLAUDE_CODE_OAUTH_TOKEN"
        return 0
    fi

    # 2. macOS Keychain
    if command -v security >/dev/null 2>&1; then
        local blob
        blob=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null)
        if [ -n "$blob" ]; then
            token=$(echo "$blob" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
            if [ -n "$token" ] && [ "$token" != "null" ]; then
                echo "$token"
                return 0
            fi
        fi
    fi

    # 3. Linux credentials file
    local creds_file="${HOME}/.claude/.credentials.json"
    if [ -f "$creds_file" ]; then
        token=$(jq -r '.claudeAiOauth.accessToken // empty' "$creds_file" 2>/dev/null)
        if [ -n "$token" ] && [ "$token" != "null" ]; then
            echo "$token"
            return 0
        fi
    fi

    # 4. GNOME Keyring via secret-tool
    if command -v secret-tool >/dev/null 2>&1; then
        local blob
        blob=$(timeout 2 secret-tool lookup service "Claude Code-credentials" 2>/dev/null)
        if [ -n "$blob" ]; then
            token=$(echo "$blob" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
            if [ -n "$token" ] && [ "$token" != "null" ]; then
                echo "$token"
                return 0
            fi
        fi
    fi

    echo ""
}

# ===== LINE 2 & 3: Usage limits with progress bars (cached) =====
_cache_dir="${TMPDIR:-/tmp}/claude-statusline"
mkdir -p "$_cache_dir"
chmod 700 "$_cache_dir"
cache_file="${_cache_dir}/usage-cache.json"
cache_max_age=60  # seconds between API calls

needs_refresh=true
usage_data=""

# Check cache
if [ -f "$cache_file" ]; then
    cache_mtime=$(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null)
    now=$(date +%s)
    cache_age=$(( now - cache_mtime ))
    if [ "$cache_age" -lt "$cache_max_age" ]; then
        needs_refresh=false
        usage_data=$(cat "$cache_file" 2>/dev/null)
    fi
fi

# Fetch fresh data if cache is stale
if $needs_refresh; then
    token=$(get_oauth_token)
    if [ -n "$token" ] && [ "$token" != "null" ]; then
        response=$(curl -s --max-time 5 \
            -H "Accept: application/json" \
            -H "Content-Type: application/json" \
            -H @<(printf "Authorization: Bearer %s" "$token") \
            -H "anthropic-beta: oauth-2025-04-20" \
            -H "User-Agent: claude-code/${cc_version}" \
            "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)
        if [ -n "$response" ] && echo "$response" | jq . >/dev/null 2>&1; then
            usage_data="$response"
            echo "$response" > "$cache_file"
        fi
    fi
    # Fall back to stale cache
    if [ -z "$usage_data" ] && [ -f "$cache_file" ]; then
        usage_data=$(cat "$cache_file" 2>/dev/null)
    fi
fi

# Cross-platform ISO to epoch conversion
# Converts ISO 8601 timestamp (e.g. "2025-06-15T12:30:00Z" or "2025-06-15T12:30:00.123+00:00") to epoch seconds.
# Properly handles UTC timestamps and converts to local time.
iso_to_epoch() {
    local iso_str="$1"

    # Try GNU date first (Linux) — handles ISO 8601 format automatically
    local epoch
    epoch=$(date -d "${iso_str}" +%s 2>/dev/null)
    if [ -n "$epoch" ]; then
        echo "$epoch"
        return 0
    fi

    # BSD date (macOS) - handle various ISO 8601 formats
    local stripped="${iso_str%%.*}"          # Remove fractional seconds (.123456)
    stripped="${stripped%%Z}"                 # Remove trailing Z
    stripped="${stripped%%+*}"                # Remove timezone offset (+00:00)
    stripped="${stripped%%-[0-9][0-9]:[0-9][0-9]}"  # Remove negative timezone offset

    # Check if timestamp is UTC (has Z or +00:00 or -00:00)
    if [[ "$iso_str" == *"Z"* ]] || [[ "$iso_str" == *"+00:00"* ]] || [[ "$iso_str" == *"-00:00"* ]]; then
        # For UTC timestamps, parse with timezone set to UTC
        epoch=$(env TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "$stripped" +%s 2>/dev/null)
    else
        epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$stripped" +%s 2>/dev/null)
    fi

    if [ -n "$epoch" ]; then
        echo "$epoch"
        return 0
    fi

    return 1
}

# Format ISO reset time to compact local time
# Usage: format_reset_time <iso_string> <style: time|datetime|date>
format_reset_time() {
    local iso_str="$1"
    local style="$2"
    [ -z "$iso_str" ] || [ "$iso_str" = "null" ] && return

    # Parse ISO datetime and convert to local time (cross-platform)
    local epoch
    epoch=$(iso_to_epoch "$iso_str")
    [ -z "$epoch" ] && return

    # Build UK-format date with ordinal suffix (e.g. "6th Mar")
    local day month suffix
    day=$(date -j -r "$epoch" +%-d 2>/dev/null || date -d "@$epoch" +%-d 2>/dev/null)
    month=$(date -j -r "$epoch" +%b 2>/dev/null || date -d "@$epoch" +%b 2>/dev/null)
    case $((day % 100)) in
        11|12|13) suffix="th" ;;
        *) case $((day % 10)) in
            1) suffix="st" ;; 2) suffix="nd" ;; 3) suffix="rd" ;; *) suffix="th" ;;
        esac ;;
    esac
    local uk_date="${day}${suffix} ${month}"

    case "$style" in
        time)
            date -j -r "$epoch" +"%H:%M" 2>/dev/null || \
            date -d "@$epoch" +"%H:%M" 2>/dev/null
            ;;
        datetime)
            local t
            t=$(date -j -r "$epoch" +"%H:%M" 2>/dev/null || date -d "@$epoch" +"%H:%M" 2>/dev/null)
            printf "%s, %s" "$uk_date" "$t"
            ;;
        *)
            printf "%s" "$uk_date"
            ;;
    esac
}

line2=""
sep=" ${dim}|${reset} "

if [ -n "$usage_data" ] && echo "$usage_data" | jq -e . >/dev/null 2>&1; then
    bar_width=7

    # ---- 5-hour (current) ----
    five_hour_pct=$(echo "$usage_data" | jq -r '.five_hour.utilization // 0' | awk '{printf "%.0f", $1}')
    five_hour_reset_iso=$(echo "$usage_data" | jq -r '.five_hour.resets_at // empty')
    five_hour_reset=$(format_reset_time "$five_hour_reset_iso" "time")
    five_hour_bar=$(build_bar "$five_hour_pct" "$bar_width")
    col1="${white}current:${reset} ${five_hour_bar}  ${cyan}${five_hour_pct}%${reset}"
    [ -n "$five_hour_reset" ] && col1+=" ${dim}(${five_hour_reset})${reset}"

    # ---- 7-day (weekly) ----
    seven_day_pct=$(echo "$usage_data" | jq -r '.seven_day.utilization // 0' | awk '{printf "%.0f", $1}')
    seven_day_reset_iso=$(echo "$usage_data" | jq -r '.seven_day.resets_at // empty')
    seven_day_reset=$(format_reset_time "$seven_day_reset_iso" "datetime")
    seven_day_bar=$(build_bar "$seven_day_pct" "$bar_width")
    col2="${white}weekly:${reset} ${seven_day_bar}  ${cyan}${seven_day_pct}%${reset}"
    [ -n "$seven_day_reset" ] && col2+=" ${dim}(${seven_day_reset})${reset}"

    # ---- Extra usage ----
    col3=""
    extra_enabled=$(echo "$usage_data" | jq -r '.extra_usage.is_enabled // false')
    if [ "$extra_enabled" = "true" ]; then
        extra_pct=$(echo "$usage_data" | jq -r '.extra_usage.utilization // 0' | awk '{printf "%.0f", $1}')
        extra_used=$(echo "$usage_data" | jq -r '.extra_usage.used_credits // 0' | awk '{printf "%.2f", $1/100}')
        extra_limit=$(echo "$usage_data" | jq -r '.extra_usage.monthly_limit // 0' | awk '{printf "%.2f", $1/100}')
        extra_bar=$(build_bar "$extra_pct" "$bar_width")

        # Next month 1st for reset date (macOS compatible)
        extra_reset="1st $(date -v+1m -v1d +%b 2>/dev/null || date -d "$(date +%Y-%m-01) +1 month" +%b 2>/dev/null)"

        col3="${white}extra:${reset} ${extra_bar}  ${cyan}\$${extra_used}/\$${extra_limit}${reset}"
        [ -n "$extra_reset" ] && col3+=" ${dim}(${extra_reset})${reset}"
    fi

    # Assemble line 2: bars row, each with its reset time in parentheses
    line2="${col1}${sep}${col2}"
    [ -n "$col3" ] && line2+="${sep}${col3}"
fi

# Append cost to the bars row (line 2)
cost_str=$(awk "BEGIN {printf \"%.2f\", $total_cost}")
cost_seg="${white}cost:${reset} ${green}\$${cost_str}${reset}"
if [ -n "$line2" ]; then
    line2+="${sep}${cost_seg}"
else
    line2="${cost_seg}"
fi

# Output all lines
printf "%b" "$line1"
[ -n "$line2" ] && printf "\n%b" "$line2"
[ -n "$line_ctx" ] && printf "\n%b" "$line_ctx"

exit 0
