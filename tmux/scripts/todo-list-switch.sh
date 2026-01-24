#!/bin/bash

# list switcher for doit tmux integration

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

CURRENT_LIST=$(get_active_list_name)

preview_list() {
    local list_file="$LISTS_DIR/${1}.json"
    if [[ -f "$list_file" ]]; then
        local total=$(jq '.todos | length' "$list_file" 2>/dev/null || echo 0)
        local pending=$(jq '[.todos[] | select(.done == false)] | length' "$list_file" 2>/dev/null || echo 0)
        local in_progress=$(jq '[.todos[] | select(.in_progress == true)] | length' "$list_file" 2>/dev/null || echo 0)
        echo "Total: $total | Pending: $pending | In Progress: $in_progress"
        echo ""
        echo "Recent items:"
        jq -r '.todos | sort_by(.order_index) | .[0:5] | .[] | "  - \(.text | split("\n")[0][0:50])"' "$list_file" 2>/dev/null
    fi
}
export -f preview_list
export LISTS_DIR

SELECTED=$(ls -1 "$LISTS_DIR"/*.json 2>/dev/null | xargs -n1 basename | sed 's/\.json$//' | \
    fzf --ansi \
        --header="Switch Todo List (current: $CURRENT_LIST)" \
        --prompt="List > " \
        --height=50% \
        --layout=reverse \
        --preview='bash -c "preview_list {}"' \
        --preview-window=right:50%:wrap)

if [[ -n "$SELECTED" && "$SELECTED" != "$CURRENT_LIST" ]]; then
    set_active_list "$SELECTED"
    tmux display-message "Switched to list: $SELECTED"
fi
