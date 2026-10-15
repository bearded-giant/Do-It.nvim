#!/bin/bash

# Owed items live twice (project list + daily) and the MCP server's syncTwin
# is the contract; these keep a tmux-side change in step with the other copy.
# Needs LISTS_DIR from get-active-list.sh.

# "<list>\t<id>" of the item's twin, empty when it has none
twin_ref() {
    jq -r --arg id "$2" '.todos[] | select(.id == $id) | .twin // empty
        | select(.list and .id) | "\(.list)\t\(.id)"' "$1" 2>/dev/null
}

# twin_apply <twin_ref> <op> [arg]; op: complete|revert|delete|restore|priority|due
# prints one status line, nothing when there is no twin
twin_apply() {
    local tlist tid op="$2" arg="${3:-}"
    IFS=$'\t' read -r tlist tid <<< "$1"
    [[ -z "$tlist" || -z "$tid" ]] && return 0
    local tpath="$LISTS_DIR/$tlist.json" filter where='.todos'
    [[ -f "$tpath" ]] || { echo "twin list \"$tlist\" is gone"; return 0; }
    [[ "$op" == restore ]] && where='(._metadata.deleted_todos // [])'
    if ! jq -e --arg id "$tid" "any(${where}[]; .id == \$id)" "$tpath" >/dev/null 2>&1; then
        echo "twin $tid no longer in \"$tlist\""
        return 0
    fi
    case "$op" in
        complete) filter='(.todos[] | select(.id == $id)) |= (.done = true | .in_progress = false
                      | .completed_at = (($arg | tonumber?) // (now | floor)))' ;;
        revert)   filter='(.todos[] | select(.id == $id)) |= (.done = false | .in_progress = false | del(.completed_at))' ;;
        priority) filter='(.todos[] | select(.id == $id)) |= (if $arg == "" then del(.priorities) else .priorities = $arg end)' ;;
        due)      filter='(.todos[] | select(.id == $id)) |= (if $arg == "" then del(.due_date) else .due_date = $arg end)' ;;
        # no promoteChildren like the MCP: tmux's own delete doesn't promote and owed twins are top-level
        delete)   filter='(.todos[] | select(.id == $id)) as $d | .todos |= map(select(.id != $id))
                      | ._metadata.deleted_todos = ([$d] + (._metadata.deleted_todos // []))[0:10]' ;;
        restore)  filter='(._metadata.deleted_todos | map(select(.id == $id)) | first) as $r
                      | .todos += [$r] | ._metadata.deleted_todos |= map(select(.id != $id))' ;;
        *) return 1 ;;
    esac
    jq --arg id "$tid" --arg arg "$arg" "$filter | ._metadata.updated_at = (now | floor)" "$tpath" \
        > "$tpath.tmp" && mv "$tpath.tmp" "$tpath"
    echo "twin in \"$tlist\": $op"
}
