#!/bin/bash

# Owed items live twice (project list + daily) and the MCP server's syncTwin
# is the contract; these keep a tmux-side change in step with the other copy.
# Needs LISTS_DIR from get-active-list.sh.

# "<list>\t<id>" of the item's twin, empty when it has none
twin_ref() {
    jq -r --arg id "$2" '.todos[] | select(.id == $id) | .twin // empty
        | select(.list and .id) | "\(.list)\t\(.id)"' "$1" 2>/dev/null
}

# twin_apply <twin_ref> <op> [arg] [notes]; op: complete|revert|delete|restore|priority|due|relink|detach
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
        # mirrors mcp/todo-text.js relabelTwin: the owed copy names its project list after the marker/type/rank prefix
        relink)   filter='(.todos[] | select(.id == $id)) |= ((.twin.list // "") as $old
                      | if $old != "" and $old != $arg then
                          ((.text // "") | capture("^(?<p>(claude:\\s*)?(\\[[^\\]]+\\]\\s*)?(\\d+[a-z]*\\.\\s+)?)").p) as $p
                          | ((.text // "")[($p | length):]) as $rest
                          | (if ($rest | startswith($old + ": ")) then .text = $p + $arg + ": " + $rest[($old | length) + 2:] else . end)
                          | (("from: " + $old + " #") as $f
                              | if ((.description // "") | startswith($f)) then .description = "from: " + $arg + " #" + .description[($f | length):] else . end)
                        else . end
                      | .twin.list = $arg)' ;;
        # mirrors mcp/server.js detachTwin: notes never sync between twins, so the deleted side's notes move over
        detach)   filter='def strip: sub("\n*----------\nlast (updated|modified):[\\s\\S]*\\z"; "");
                      def trimws: sub("\\A\\s+"; "") | sub("\\s+\\z"; "");
                      ($notes | strip | trimws | if startswith($hdr) then .[($hdr | length):] | trimws else . end) as $n
                      | (.todos[] | select(.id == $id)) |= (
                          ((.description // "") | strip | sub("\\s+\\z"; "")) as $body
                          | .description = ([$body,
                                (if $n != "" and ($body | contains($n) | not) then "notes from \"\($arg)\":\n\($n)" else empty end),
                                "list \"\($arg)\" deleted \(now | strflocaltime("%Y-%m-%d")); twin link dropped"]
                              | map(select(. != "")) | join("\n\n"))
                              + "\n\n\n----------\nlast modified: \(now | strflocaltime("%Y-%m-%d: %H:%M"))"
                          | del(.twin))' ;;
        # no promoteChildren like the MCP: tmux's own delete doesn't promote and owed twins are top-level
        delete)   filter='(.todos[] | select(.id == $id)) as $d | .todos |= map(select(.id != $id))
                      | ._metadata.deleted_todos = ([$d] + (._metadata.deleted_todos // []))[0:10]' ;;
        restore)  filter='(._metadata.deleted_todos | map(select(.id == $id)) | first) as $r
                      | .todos += [$r] | ._metadata.deleted_todos |= map(select(.id != $id))' ;;
        *) return 1 ;;
    esac
    jq --arg id "$tid" --arg arg "$arg" --arg notes "${4:-}" --arg hdr "$tlist: $tid" \
        "$filter | ._metadata.updated_at = (now | floor)" "$tpath" \
        > "$tpath.tmp" && mv "$tpath.tmp" "$tpath"
    echo "twin in \"$tlist\": $op"
}

# twin_detach_list <list_path> <list_name>: before a list goes, unlink every twin it holds on another list
twin_detach_list() {
    local id
    for id in $(jq -r --arg l "$2" '.todos[] | select(.twin.list and .twin.id and .twin.list != $l) | .id' "$1" 2>/dev/null); do
        twin_apply "$(twin_ref "$1" "$id")" detach "$2" \
            "$(jq -r --arg id "$id" '.todos[] | select(.id == $id) | .description // ""' "$1")"
    done
}
