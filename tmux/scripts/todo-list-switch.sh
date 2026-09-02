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
        echo "Total: $total | Pending: $pending | In Progress: $in_progress"
        echo ""
        echo "Recent items:"
        jq -r --argjson w "$text_w" '.todos | sort_by(.order_index) | .[0:5] | .[] | "  - \(.text | split("\n")[0][0:$w])"' "$list_file" 2>/dev/null
    fi
}
export -f preview_list
export LISTS_DIR

# " [sess1 sess2]" for lists some session links; dead sessions render dim
badge_for_list() {
    local badge="" s
    while IFS= read -r s; do
        [[ -z "$s" ]] && continue
        if grep -qxF -- "$s" <<< "$LIVE_SESSIONS"; then
            badge+=" $s"
        else
            badge+=" ${COLOR_DIM}${s}${COLOR_RESET}"
        fi
    done < <(sessions_for_list "$1")
    [[ -n "$badge" ]] && printf ' [%s]' "${badge# }"
}

# daily pinned to the top with its pending count, the rest as-is
build_rows() {
    local name pending
    if [[ -f "$LISTS_DIR/daily.json" ]]; then
        pending=$(jq '[.todos[] | select(.done == false)] | length' "$LISTS_DIR/daily.json" 2>/dev/null || echo 0)
        printf 'daily (%s pending)%s\n' "$pending" "$(badge_for_list daily)"
    fi
    while IFS= read -r name; do
        [[ -z "$name" || "$name" == "daily" ]] && continue
        printf '%s%s\n' "$name" "$(badge_for_list "$name")"
    done < <(get_available_lists)
}

if [[ -n "$SESS" ]]; then
    HEADER="Lists — session: $SESS → $CURRENT_LIST
ENTER: link to session   g: set global only   u: unlink session"
else
    HEADER="Switch Todo List (current: $CURRENT_LIST)
ENTER: switch   g: set global"
fi

RESULT=$(build_rows | \
    fzf --ansi \
        --header="$HEADER" \
        --prompt="List > " \
        --height=100% \
        --layout=reverse \
        --expect=g,u \
        --preview='bash -c "preview_list {}"' \
        --preview-window=right:50%:wrap)

KEY=$(echo "$RESULT" | head -1)
SELECTED=$(echo "$RESULT" | tail -1 | awk '{print $1}')

case "$KEY" in
    "u")
        if [[ -n "$SESS" ]]; then
            unlink_session "$SESS"
            echo "Unlinked session '$SESS' (falls back to global list)"
        fi
        ;;
    "g")
        [[ -n "$SELECTED" ]] && set_global_list "$SELECTED"
        ;;
    *)
        [[ -n "$SELECTED" ]] && set_active_list "$SELECTED"
        ;;
esac
