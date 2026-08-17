#!/bin/bash

# get the active todo list path from session.json or environment
# priority: DOIT_ACTIVE_LIST env var > session.json > default (daily)

DOIT_DATA_DIR="${DOIT_DATA_DIR:-$HOME/.local/share/nvim/doit}"
SESSION_FILE="$DOIT_DATA_DIR/session.json"
LISTS_DIR="$DOIT_DATA_DIR/lists"

# Mirror of state/project_list.lua's sanitize(). A list name becomes a filename,
# so keep it to path-safe characters. Dots are KEPT on purpose: repos like
# "do-it.nvim" would otherwise collapse to "do-itnvim" and resolve to a different
# list than nvim uses. Keep both implementations in sync.
sanitize_list_name() {
    local clean
    clean=$(printf '%s' "$1" | tr -s '[:space:]' '_' | tr -cd '[:alnum:]._-')
    [[ "$clean" == "." || "$clean" == ".." ]] && clean=""
    printf '%s' "$clean"
}

# Name of the list for a git repo containing $1, empty when not in a repo.
derive_project_list() {
    local dir="${1:-$PWD}" root
    root=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || return 1
    [[ -z "$root" ]] && return 1
    sanitize_list_name "$(basename "$root")"
}

# Opt-in via `set -g @doit-project-lists on`. Resolution lives here rather than
# in DOIT_ACTIVE_LIST because several scripts deliberately unset that var, which
# would silently drop the derived list.
project_lists_enabled() {
    [[ -n "$TMUX" ]] || return 1
    command -v tmux &>/dev/null || return 1
    local opt
    opt=$(tmux show-option -gqv @doit-project-lists 2>/dev/null)
    [[ "$opt" == "on" || "$opt" == "1" || "$opt" == "true" ]]
}

get_active_list_name() {
    local list_name="" derived=""

    # check env var first, then the derived project list, then session.json
    if [[ -n "$DOIT_ACTIVE_LIST" ]]; then
        list_name="$DOIT_ACTIVE_LIST"
    elif project_lists_enabled; then
        local pane_cwd
        # run-shell bindings do not inherit the pane's cwd, so ask tmux for it
        pane_cwd=$(tmux display-message -p '#{pane_current_path}' 2>/dev/null)
        list_name=$(derive_project_list "${pane_cwd:-$PWD}") || list_name=""
        [[ -n "$list_name" ]] && derived=1
    fi

    if [[ -z "$list_name" ]] && [[ -f "$SESSION_FILE" ]] && command -v jq &> /dev/null; then
        list_name=$(jq -r '.active_list // "daily"' "$SESSION_FILE" 2>/dev/null)
    fi
    [[ -z "$list_name" || "$list_name" == "null" ]] && list_name="daily"

    # a project list is created on first use, the same way nvim's load_list does;
    # without this the missing-file fallback below would bounce us back to daily
    if [[ -n "$derived" && ! -f "$LISTS_DIR/${list_name}.json" ]]; then
        mkdir -p "$LISTS_DIR"
        printf '{"_metadata":{"created_at":%s,"updated_at":%s},"todos":[],"notes":[]}\n' \
            "$(date +%s)" "$(date +%s)" > "$LISTS_DIR/${list_name}.json"
    fi

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
