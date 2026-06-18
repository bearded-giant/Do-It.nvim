#!/bin/bash

# get the active todo list path from session.json or environment
# priority: DOIT_ACTIVE_LIST env var > session.json > default (daily)

DOIT_DATA_DIR="${DOIT_DATA_DIR:-$HOME/.local/share/nvim/doit}"
SESSION_FILE="$DOIT_DATA_DIR/session.json"
LISTS_DIR="$DOIT_DATA_DIR/lists"

get_active_list_name() {
    local list_name=""

    # check env var first, then session.json
    if [[ -n "$DOIT_ACTIVE_LIST" ]]; then
        list_name="$DOIT_ACTIVE_LIST"
    elif [[ -f "$SESSION_FILE" ]] && command -v jq &> /dev/null; then
        list_name=$(jq -r '.active_list // "daily"' "$SESSION_FILE" 2>/dev/null)
    fi
    [[ -z "$list_name" || "$list_name" == "null" ]] && list_name="daily"

    # active list deleted out from under us? fall back so the UI still opens
    # instead of resolving to a missing file and exiting
    if [[ ! -f "$LISTS_DIR/${list_name}.json" ]]; then
        if [[ -f "$LISTS_DIR/daily.json" ]]; then
            list_name="daily"
        else
            local first
            first=$(ls -1 "$LISTS_DIR"/*.json 2>/dev/null | head -1)
            [[ -n "$first" ]] && list_name=$(basename "$first" .json)
        fi
    fi

    echo "$list_name"
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
