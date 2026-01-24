#!/bin/bash

# get the active todo list path from session.json or environment
# priority: DOIT_ACTIVE_LIST env var > session.json > default (daily)

DOIT_DATA_DIR="${DOIT_DATA_DIR:-$HOME/.local/share/nvim/doit}"
SESSION_FILE="$DOIT_DATA_DIR/session.json"
LISTS_DIR="$DOIT_DATA_DIR/lists"

get_active_list_name() {
    # check env var first
    if [[ -n "$DOIT_ACTIVE_LIST" ]]; then
        echo "$DOIT_ACTIVE_LIST"
        return
    fi

    # read from session.json
    if [[ -f "$SESSION_FILE" ]] && command -v jq &> /dev/null; then
        local list_name
        list_name=$(jq -r '.active_list // "daily"' "$SESSION_FILE" 2>/dev/null)
        if [[ -n "$list_name" && "$list_name" != "null" ]]; then
            echo "$list_name"
            return
        fi
    fi

    # default fallback
    echo "daily"
}

get_active_list_path() {
    local list_name
    list_name=$(get_active_list_name)
    echo "$LISTS_DIR/${list_name}.json"
}

set_active_list() {
    local list_name="$1"
    if [[ -z "$list_name" ]]; then
        echo "Error: list name required" >&2
        return 1
    fi

    # update session.json
    if [[ -f "$SESSION_FILE" ]]; then
        jq --arg list "$list_name" '.active_list = $list' \
            "$SESSION_FILE" > "${SESSION_FILE}.tmp" && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"
    else
        mkdir -p "$(dirname "$SESSION_FILE")"
        echo "{\"active_list\": \"$list_name\"}" > "$SESSION_FILE"
    fi

    # update tmux environment if in tmux
    if [[ -n "$TMUX" ]]; then
        tmux set-environment -g DOIT_ACTIVE_LIST "$list_name"
    fi
}

get_available_lists() {
    ls -1 "$LISTS_DIR"/*.json 2>/dev/null | xargs -n1 basename | sed 's/\.json$//'
}

# if sourced, functions are available
# if executed directly, output the path
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-path}" in
        name)
            get_active_list_name
            ;;
        path|*)
            get_active_list_path
            ;;
    esac
fi
