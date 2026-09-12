#!/bin/bash

# list switcher for doit tmux integration
# ENTER links the list to the current tmux session (and refreshes the global
# pointer); g sets the global pointer only; u unlinks the current session.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/get-active-list.sh"

DOIT_DATA_DIR="${DOIT_DATA_DIR:-$HOME/.local/share/nvim/doit}"
LISTS_DIR="$DOIT_DATA_DIR/lists"
SESSION_FILE="$DOIT_DATA_DIR/session.json"

if ! command -v jq &> /dev/null; then
    echo "Error: jq is required"
    exit 1
fi

if ! command -v fzf &> /dev/null; then
    echo "Error: fzf is required"
    exit 1
fi

COLOR_DIM=$'\e[2m'
COLOR_RED=$'\e[1;31m'
COLOR_YELLOW=$'\e[1;33m'
COLOR_DIM_YELLOW=$'\e[2;33m'
COLOR_RESET=$'\e[0m'

CURRENT_LIST=$(get_active_list_name)
SESS=$(get_tmux_session_name 2>/dev/null) || SESS=""
LIVE_SESSIONS=$(tmux list-sessions -F '#S' 2>/dev/null)

preview_list() {
    # rows carry markers/badges — first word after any "* " marker is the name
    local name
    name=$(printf '%s' "$1" | sed 's/^[* ]*//' | awk '{print $1}')
    local list_file="$LISTS_DIR/${name}.json"
    # truncate to the preview pane, not a fixed column count (fzf exports this)
    local text_w=$(( ${FZF_PREVIEW_COLUMNS:-0} - 4 ))
    (( text_w < 20 )) && text_w=200
    if [[ -f "$list_file" ]]; then
        local total=$(jq '.todos | length' "$list_file" 2>/dev/null || echo 0)
        local pending=$(jq '[.todos[] | select(.done == false)] | length' "$list_file" 2>/dev/null || echo 0)
        local in_progress=$(jq '[.todos[] | select(.in_progress == true)] | length' "$list_file" 2>/dev/null || echo 0)
        local overdue=$(jq -r --arg today "$(date +%F)" '[.todos[]? | select((.done | not) and ((.due_date // "") != "") and .due_date < $today)] | length' "$list_file" 2>/dev/null || echo 0)
        echo "Total: $total | Pending: $pending | In Progress: $in_progress"
        [[ "$overdue" -gt 0 ]] 2>/dev/null && printf '%s%s overdue%s\n' "$COLOR_RED" "$overdue" "$COLOR_RESET"
        echo ""
        echo "Recent items:"
        jq -r --argjson w "$text_w" '.todos | sort_by(.order_index) | .[0:5] | .[] | "  - \(.text | split("\n")[0][0:$w])"' "$list_file" 2>/dev/null
    fi
}
export -f preview_list
export LISTS_DIR
export COLOR_RED
export COLOR_RESET

# " !2 overdue" when the list has open items past their due date
overdue_badge_for_list() {
    local n
    n=$(overdue_count_for_list "$1")
    [[ "$n" =~ ^[0-9]+$ ]] || return 0
    (( n > 0 )) && printf ' %s!%s overdue%s' "$COLOR_RED" "$n" "$COLOR_RESET"
    return 0
}

# " [sess1 sess2]" for lists some session links; dead sessions render dim
badge_for_list() {
    local badge="" s
    while IFS= read -r s; do
        [[ -z "$s" ]] && continue
        if grep -qxF -- "$s" <<< "$LIVE_SESSIONS"; then
            badge+=" ${COLOR_YELLOW}${s}${COLOR_RESET}"
        else
            badge+=" ${COLOR_DIM_YELLOW}${s}${COLOR_RESET}"
        fi
    done < <(sessions_for_list "$1")
    [[ -n "$badge" ]] && printf ' [%s]' "${badge# }"
}

# daily pinned to the top with its pending count, the rest as-is
build_rows() {
    local name pending
    if [[ -f "$LISTS_DIR/daily.json" ]]; then
        pending=$(jq '[.todos[] | select(.done == false)] | length' "$LISTS_DIR/daily.json" 2>/dev/null || echo 0)
        printf 'daily (%s pending)%s%s\n' "$pending" \
            "$(overdue_badge_for_list daily)" "$(badge_for_list daily)"
    fi
    while IFS= read -r name; do
        [[ -z "$name" || "$name" == "daily" ]] && continue
        printf '%s%s%s\n' "$name" \
            "$(overdue_badge_for_list "$name")" "$(badge_for_list "$name")"
    done < <(get_available_lists)
}

if [[ -n "$SESS" ]]; then
    HEADER="Lists — session: $SESS → $CURRENT_LIST
ENTER: link to session   ctrl-g: set global only   ctrl-u: unlink session"
else
    HEADER="Switch Todo List (current: $CURRENT_LIST)
ENTER: switch   ctrl-g: set global"
fi

RESULT=$(build_rows | \
    fzf --ansi \
        --header="$HEADER" \
        --prompt="List > " \
        --height=100% \
        --layout=reverse \
        --expect=ctrl-g,ctrl-u \
        --preview='bash -c "preview_list {}"' \
        --preview-window=right:50%:wrap)

KEY=$(echo "$RESULT" | head -1)
SELECTED=$(echo "$RESULT" | tail -1 | awk '{print $1}')

case "$KEY" in
    "ctrl-u")
        if [[ -n "$SESS" ]]; then
            unlink_session "$SESS"
            echo "Unlinked session '$SESS' (falls back to global list)"
        fi
        ;;
    "ctrl-g")
        [[ -n "$SELECTED" ]] && set_global_list "$SELECTED"
        ;;
    *)
        [[ -n "$SELECTED" ]] && set_active_list "$SELECTED"
        ;;
esac
