#!/bin/bash

# List source: a list is the user's when `_metadata.source` is "user" (or it is
# daily); anything else, unflagged included, counts as claude. The view filter
# lives in session.json `source_filter` so every surface shares one toggle.
# Needs get-active-list.sh sourced first (SESSION_FILE, LISTS_DIR, _update_session_file).

DOIT_SOURCE_JQ='def is_mine($name): $name == "daily" or (._metadata.source? == "user");'

source_filter() {
    local f=""
    [[ -f "$SESSION_FILE" ]] && f=$(jq -r '.source_filter // empty' "$SESSION_FILE" 2>/dev/null)
    case "$f" in mine|claude) echo "$f" ;; *) echo all ;; esac
}

# all -> mine -> claude -> all; prints the new value
cycle_source_filter() {
    local next
    case "$(source_filter)" in all) next=mine ;; mine) next=claude ;; *) next=all ;; esac
    _update_session_file --arg f "$next" '.source_filter = $f' && echo "$next"
}

list_is_mine() {
    local name=$1 file="$LISTS_DIR/$1.json"
    [[ "$name" == daily ]] && return 0
    [[ -f "$file" ]] && [[ "$(jq -r '._metadata.source? // empty' "$file" 2>/dev/null)" == user ]]
}

mine_badge() {
    list_is_mine "$1" && printf ' \033[32mmine\033[0m'
    return 0
}

# true when list $1 shows under the current filter
list_in_filter() {
    case "${2:-$(source_filter)}" in
        mine) list_is_mine "$1" ;;
        claude) ! list_is_mine "$1" ;;
        *) return 0 ;;
    esac
}

# flips list $1 between user and mcp; prints the new source. daily stays the user's.
toggle_list_source() {
    local file="$LISTS_DIR/$1.json" next
    [[ "$1" == daily ]] && { echo user; return 0; }
    [[ -f "$file" ]] || return 1
    if list_is_mine "$1"; then next=mcp; else next=user; fi
    jq --arg s "$next" '._metadata = ((._metadata // {}) + {source: $s, updated_at: (now | floor)})' "$file" \
        > "$file.tmp" && mv "$file.tmp" "$file" && echo "$next"
}
