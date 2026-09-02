#!/bin/bash

# get the active todo list path from session.json or environment
# priority: DOIT_PINNED_LIST > DOIT_ACTIVE_LIST env var > per-tmux-session link
#           (sessions map in session.json) > derived project list > global
#           .active_list > default (daily)

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

# Current tmux session name, empty outside tmux. DOIT_SESSION_NAME overrides:
# the status bar passes #{session_name} through it because #() commands run
# without a client context, and tests use it to fake a session.
get_tmux_session_name() {
    if [[ -n "$DOIT_SESSION_NAME" ]]; then
        printf '%s' "$DOIT_SESSION_NAME"
        return 0
    fi
    [[ -n "$TMUX" ]] || return 1
    command -v tmux &>/dev/null || return 1
    if [[ -n "$TMUX_PANE" ]]; then
        tmux display-message -p -t "$TMUX_PANE" '#S' 2>/dev/null
    else
        tmux display-message -p '#S' 2>/dev/null
    fi
}

# read-modify-write session.json with a jq filter; preserves unrelated keys
_update_session_file() {
    command -v jq &>/dev/null || return 1
    mkdir -p "$(dirname "$SESSION_FILE")"
    [[ -f "$SESSION_FILE" ]] || echo '{}' > "$SESSION_FILE"
    jq "$@" "$SESSION_FILE" > "${SESSION_FILE}.tmp" && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"
}

# List linked to session $1, empty when unlinked.
get_session_link() {
    [[ -f "$SESSION_FILE" ]] || return 1
    command -v jq &>/dev/null || return 1
    jq -r --arg s "$1" '(.sessions? // {})[$s] // empty' "$SESSION_FILE" 2>/dev/null
}

# Link session $1 to list $2.
link_session() {
    [[ -n "$1" && -n "$2" ]] || return 1
    _update_session_file --arg s "$1" --arg l "$2" '.sessions = (.sessions? // {}) + {($s): $l}'
}

# Drop session $1's link; it falls back to the global chain.
unlink_session() {
    [[ -n "$1" ]] || return 1
    _update_session_file --arg s "$1" 'if .sessions? then .sessions |= with_entries(select(.key != $s)) else . end'
}

# Point every link at list $1 to list $2 (list rename).
relink_sessions_for_list() {
    [[ -f "$SESSION_FILE" ]] || return 0
    _update_session_file --arg old "$1" --arg new "$2" \
        'if .sessions? then .sessions |= with_entries(if .value == $old then .value = $new else . end) else . end'
}

# Drop every link at list $1 (list deleted).
prune_links_for_list() {
    [[ -f "$SESSION_FILE" ]] || return 0
    _update_session_file --arg l "$1" \
        'if .sessions? then .sessions |= with_entries(select(.value != $l)) else . end'
}

# Session names linked to list $1, one per line.
sessions_for_list() {
    [[ -f "$SESSION_FILE" ]] || return 0
    command -v jq &>/dev/null || return 0
    jq -r --arg l "$1" '(.sessions? // {}) | to_entries[] | select(.value == $l) | .key' "$SESSION_FILE" 2>/dev/null
}

get_active_list_name() {
    local list_name="" ensure="" sess link

    if [[ -n "$DOIT_PINNED_LIST" ]]; then
        # pinned popup (e.g. the daily view): fixed list, created on first use
        list_name="$DOIT_PINNED_LIST"
        ensure=1
    elif [[ -n "$DOIT_ACTIVE_LIST" ]]; then
        list_name="$DOIT_ACTIVE_LIST"
    fi

    if [[ -z "$list_name" ]]; then
        sess=$(get_tmux_session_name 2>/dev/null) || sess=""
        if [[ -n "$sess" ]]; then
            link=$(get_session_link "$sess") || link=""
            # a link to a deleted list is ignored so the chain keeps resolving
            [[ -n "$link" && -f "$LISTS_DIR/${link}.json" ]] && list_name="$link"
        fi
    fi

    if [[ -z "$list_name" ]] && project_lists_enabled; then
        local pane_cwd
        # run-shell bindings do not inherit the pane's cwd, so ask tmux for it
        pane_cwd=$(tmux display-message -p '#{pane_current_path}' 2>/dev/null)
        list_name=$(derive_project_list "${pane_cwd:-$PWD}") || list_name=""
        [[ -n "$list_name" ]] && ensure=1
    fi

    if [[ -z "$list_name" ]] && [[ -f "$SESSION_FILE" ]] && command -v jq &> /dev/null; then
        list_name=$(jq -r '.active_list // "daily"' "$SESSION_FILE" 2>/dev/null)
    fi
    [[ -z "$list_name" || "$list_name" == "null" ]] && list_name="daily"

    # derived/pinned lists are created on first use, the same way nvim's
    # load_list does; without this the missing-file fallback below would
    # bounce us back to daily
    if [[ -n "$ensure" && ! -f "$LISTS_DIR/${list_name}.json" ]]; then
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

# Switch the active list: writes the global pointer, and inside tmux also
# links the current session (every in-tmux switch updates both).
set_active_list() {
    local list_name="$1"
    if [[ -z "$list_name" ]]; then
        echo "Error: list name required" >&2
        return 1
    fi

    set_global_list "$list_name" || return 1

    local sess
    sess=$(get_tmux_session_name 2>/dev/null) || sess=""
    [[ -n "$sess" ]] && link_session "$sess" "$list_name"
    return 0
}

# Global pointer only — what non-tmux contexts fall back to.
set_global_list() {
    local list_name="$1"
    if [[ -z "$list_name" ]]; then
        echo "Error: list name required" >&2
        return 1
    fi
    _update_session_file --arg list "$list_name" '.active_list = $list'
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
