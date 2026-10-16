#!/bin/bash

# get the active todo list path from session.json or environment
# priority: DOIT_PINNED_LIST > DOIT_ACTIVE_LIST env var > per-tmux-window link
#           (the window's @doit-window-list option; session.json's sessions map,
#           keyed "<session>:<window>", restores it after a tmux restart) >
#           derived project list > daily.
#           the global .active_list pointer only applies outside tmux.

DOIT_DATA_DIR="${DOIT_DATA_DIR:-$HOME/.local/share/nvim/doit}"
SESSION_FILE="$DOIT_DATA_DIR/session.json"
LISTS_DIR="$DOIT_DATA_DIR/lists"
# field separator for tmux format output; window names can hold tabs and spaces
DOIT_SEP=$'\x1f'

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

# tmux target for "this window". DOIT_WINDOW wins: the status bar passes
# #{window_id} through it because #() commands run without a client context,
# and by hand '<session>:<window>' works. Then this pane, then a popup's session
# from $TMUX. Succeeds with empty output for the untargeted call.
_doit_tmux_target() {
    if [[ -n "$DOIT_WINDOW" ]]; then
        printf '%s' "$DOIT_WINDOW"
        return 0
    fi
    [[ -n "$TMUX" ]] || return 1
    if [[ -n "$TMUX_PANE" ]]; then
        printf '%s' "$TMUX_PANE"
        return 0
    fi
    # popups have no TMUX_PANE; $TMUX ends in the session id, whose current window is the one under the popup
    local sid="${TMUX##*,}"
    [[ "$sid" =~ ^[0-9]+$ ]] && printf '%s' "\$$sid"
    return 0
}

# "<window id>␟<live link>␟<session>:<window>" for this window; fails outside tmux.
get_tmux_window_info() {
    command -v tmux &>/dev/null || return 1
    local target args=() out
    target=$(_doit_tmux_target) || return 1
    [[ -n "$target" ]] && args=(-t "$target")
    out=$(tmux display-message -p "${args[@]}" "#{window_id}${DOIT_SEP}#{@doit-window-list}${DOIT_SEP}#S:#W" 2>/dev/null)
    [[ -n "$out" ]] || return 1
    printf '%s' "$out"
}

# "<session>:<window name>" for this window, the key its link persists under.
# tmux bans ':' in session names, so the first ':' splits it.
get_tmux_window_key() {
    local info
    info=$(get_tmux_window_info) || return 1
    printf '%s' "${info#*"$DOIT_SEP"*"$DOIT_SEP"}"
}

# True when a live window other than $2 already holds the persisted link for key $1.
_key_claimed_elsewhere() {
    tmux list-windows -a -F "#{window_id}${DOIT_SEP}#{@doit-window-key}" 2>/dev/null |
        K="$1" ID="$2" awk -F"$DOIT_SEP" '$1 != ENVIRON["ID"] && $2 == ENVIRON["K"] {found=1} END {exit !found}'
}

# Live link of window $1 to list $2, stamped with the key $3 it persists under
# so a rename can move the persisted copy (todo-relink.sh).
_set_window_options() {
    tmux set-option -wq -t "$1" @doit-window-list "$2" 2>/dev/null
    tmux set-option -wq -t "$1" @doit-window-key "$3" 2>/dev/null
}

_unset_window_options() {
    tmux set-option -wqu -t "$1" @doit-window-list 2>/dev/null
    tmux set-option -wqu -t "$1" @doit-window-key 2>/dev/null
}

# Live windows linked to list $1 now link list $2; an empty $2 unlinks them.
_retag_live_windows() {
    [[ -n "$TMUX" ]] && command -v tmux &>/dev/null || return 0
    local id list
    while IFS="$DOIT_SEP" read -r id list; do
        [[ -n "$list" && "$list" == "$1" ]] || continue
        if [[ -n "$2" ]]; then
            tmux set-option -wq -t "$id" @doit-window-list "$2" 2>/dev/null
        else
            _unset_window_options "$id"
        fi
    done < <(tmux list-windows -a -F "#{window_id}${DOIT_SEP}#{@doit-window-list}" 2>/dev/null)
}

# read-modify-write session.json with a jq filter; preserves unrelated keys
_update_session_file() {
    command -v jq &>/dev/null || return 1
    mkdir -p "$(dirname "$SESSION_FILE")"
    [[ -f "$SESSION_FILE" ]] || echo '{}' > "$SESSION_FILE"
    jq "$@" "$SESSION_FILE" > "${SESSION_FILE}.tmp" && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"
}

# List persisted for window key $1, empty when unlinked.
get_window_link() {
    [[ -f "$SESSION_FILE" ]] || return 1
    command -v jq &>/dev/null || return 1
    jq -r --arg s "$1" '(.sessions? // {})[$s] // empty' "$SESSION_FILE" 2>/dev/null
}

# Persist window key $1's link to list $2.
link_window() {
    [[ -n "$1" && -n "$2" ]] || return 1
    _update_session_file --arg s "$1" --arg l "$2" '.sessions = (.sessions? // {}) + {($s): $l}'
}

# Drop window key $1's persisted link.
unlink_window() {
    [[ -n "$1" ]] || return 1
    _update_session_file --arg s "$1" 'if .sessions? then .sessions |= with_entries(select(.key != $s)) else . end'
}

# List linked to this window: its live @doit-window-list option, else the link
# persisted under its name (a tmux restart drops window options), which it
# adopts unless another live window already holds that name's link. Fails
# outside tmux; succeeds with empty output when the window is unlinked.
get_current_window_link() {
    local info id live key link
    info=$(get_tmux_window_info) || return 1
    IFS="$DOIT_SEP" read -r id live key <<< "$info"
    if [[ -n "$live" ]]; then
        printf '%s' "$live"
        return 0
    fi
    link=$(get_window_link "$key") || link=""
    [[ -n "$link" && -f "$LISTS_DIR/${link}.json" ]] || return 0
    _key_claimed_elsewhere "$key" "$id" && return 0
    _set_window_options "$id" "$link" "$key"
    printf '%s' "$link"
}

# Link this window to list $1: the live option plus its persisted copy.
link_current_window() {
    [[ -n "$1" ]] || return 1
    local info id live key
    info=$(get_tmux_window_info) || return 1
    IFS="$DOIT_SEP" read -r id live key <<< "$info"
    _set_window_options "$id" "$1" "$key"
    link_window "$key" "$1"
}

# Unlink this window; it falls back to daily.
unlink_current_window() {
    local info id live key
    info=$(get_tmux_window_info) || return 1
    IFS="$DOIT_SEP" read -r id live key <<< "$info"
    _unset_window_options "$id"
    # a same-named window may hold the persisted link; leave it to that window
    _key_claimed_elsewhere "$key" "$id" || unlink_window "$key"
}

# Point every link at list $1 to list $2 (list rename).
relink_windows_for_list() {
    _retag_live_windows "$1" "$2"
    [[ -f "$SESSION_FILE" ]] || return 0
    _update_session_file --arg old "$1" --arg new "$2" \
        'if .sessions? then .sessions |= with_entries(if .value == $old then .value = $new else . end) else . end'
}

# Drop every link at list $1 (list deleted).
prune_links_for_list() {
    _retag_live_windows "$1" ""
    [[ -f "$SESSION_FILE" ]] || return 0
    _update_session_file --arg l "$1" \
        'if .sessions? then .sessions |= with_entries(select(.value != $l)) else . end'
}

# Window keys linked to list $1, one per line.
windows_for_list() {
    [[ -f "$SESSION_FILE" ]] || return 0
    command -v jq &>/dev/null || return 0
    jq -r --arg l "$1" '(.sessions? // {}) | to_entries[] | select(.value == $l) | .key' "$SESSION_FILE" 2>/dev/null
}

get_active_list_name() {
    local list_name="" ensure="" in_tmux="" link

    if [[ -n "$DOIT_PINNED_LIST" ]]; then
        # pinned popup (e.g. the daily view): fixed list, created on first use
        list_name="$DOIT_PINNED_LIST"
        ensure=1
    elif [[ -n "$DOIT_ACTIVE_LIST" ]]; then
        list_name="$DOIT_ACTIVE_LIST"
    fi

    if [[ -z "$list_name" ]] && link=$(get_current_window_link 2>/dev/null); then
        in_tmux=1
        # a link to a deleted list is ignored so the chain keeps resolving
        [[ -n "$link" && -f "$LISTS_DIR/${link}.json" ]] && list_name="$link"
    fi

    if [[ -z "$list_name" ]] && project_lists_enabled; then
        local pane_cwd target args=()
        # run-shell bindings do not inherit the pane's cwd, so ask tmux for it
        target=$(_doit_tmux_target 2>/dev/null) || target=""
        [[ -n "$target" ]] && args=(-t "$target")
        pane_cwd=$(tmux display-message -p "${args[@]}" '#{pane_current_path}' 2>/dev/null)
        list_name=$(derive_project_list "${pane_cwd:-$PWD}") || list_name=""
        [[ -n "$list_name" ]] && ensure=1
    fi

    # inside tmux an unlinked window is daily, not whatever list was switched
    # to last somewhere else; the global pointer is the outside-tmux default
    if [[ -z "$list_name" && -z "$in_tmux" ]] && [[ -f "$SESSION_FILE" ]] && command -v jq &> /dev/null; then
        list_name=$(jq -r '.active_list // "daily"' "$SESSION_FILE" 2>/dev/null)
    fi
    [[ -z "$list_name" || "$list_name" == "null" ]] && list_name="daily"
    # daily self-creates like nvim's load_list, so the default never bounces to some other list
    [[ "$list_name" == "daily" ]] && ensure=1

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
# links the current window (every in-tmux switch updates both).
set_active_list() {
    local list_name="$1"
    if [[ -z "$list_name" ]]; then
        echo "Error: list name required" >&2
        return 1
    fi

    set_global_list "$list_name" || return 1

    link_current_window "$list_name" 2>/dev/null
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

# Open todos past their due date in list $1, for the list views' overdue badge.
# ISO dates compare correctly as strings, so no date math in jq.
overdue_count_for_list() {
    local file="$LISTS_DIR/${1}.json"
    if [[ ! -f "$file" ]] || ! command -v jq &>/dev/null; then
        printf '0'
        return
    fi
    jq -r --arg today "$(date +%F)" \
        '[.todos[]? | select((.done | not) and ((.due_date // "") != "") and .due_date < $today)] | length' \
        "$file" 2>/dev/null || printf '0'
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
