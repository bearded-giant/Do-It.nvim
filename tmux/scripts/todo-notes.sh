#!/bin/bash

# List-scoped scratch notes modal for tmux (fzf). CRUD on the active list's
# top-level `notes` array — the same list JSON nvim reads/writes.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/get-active-list.sh"

unset DOIT_ACTIVE_LIST
TODO_LIST_PATH="$(get_active_list_path)"
ACTIVE_LIST_NAME="$(get_active_list_name)"

command -v jq &>/dev/null || { echo "Error: jq is required"; exit 1; }
command -v fzf &>/dev/null || { echo "Error: fzf is required"; exit 1; }
[[ -f "$TODO_LIST_PATH" ]] || { echo "Error: list not found at $TODO_LIST_PATH"; exit 1; }

COLOR_RESET=$'\e[0m'
COLOR_DIM=$'\e[2m'
COLOR_PURPLE=$'\e[38;5;141m'

USE_EDITOR=$(tmux show-option -gqv "@doit-use-editor")
[[ "$USE_EDITOR" == "true" ]] && USE_EDITOR=true || USE_EDITOR=false

export TODO_LIST_PATH

new_note_id() { echo "$(date +%s)_$RANDOM"; }

clip() {
    if command -v pbcopy &>/dev/null; then pbcopy
    elif command -v xclip &>/dev/null; then xclip -selection clipboard
    elif command -v xsel &>/dev/null; then xsel --clipboard
    else return 1
    fi
}

# atomic jq read-modify-write of the list file
write_list() {
    local tmp="${TODO_LIST_PATH}.tmp"
    if jq "$@" "$TODO_LIST_PATH" > "$tmp"; then
        mv "$tmp" "$TODO_LIST_PATH"
    else
        rm -f "$tmp"
        return 1
    fi
}

# single-line input via fzf; returns 130 only on cancel (esc/ctrl-c).
# NB: fzf exits non-zero (1/2) when accepting a query against an empty item
# list — that is normal here, NOT a cancel. Only 130 means the user aborted.
input_line() {
    local prefill="$1" header="$2" result status
    result=$(true | fzf --print-query --query="$prefill" \
        --height=4 --layout=reverse --no-info \
        --header="$header" \
        --bind 'enter:accept' --bind 'esc:abort')
    status=$?
    [[ $status -eq 130 ]] && return 130
    echo "$result" | head -1
}

# multi-line body editor (temp file + editor). The editor's UI MUST go to the
# terminal, but this function runs inside $(...) so its stdout is a pipe — force
# the editor's stdin/stdout to /dev/tty so it renders, then emit the file body.
edit_body() {
    local prefill="$1" tmp
    tmp=$(mktemp /tmp/doit_note.XXXXXX)
    [[ -n "$prefill" ]] && printf '%s' "$prefill" > "$tmp"
    if [[ "$USE_EDITOR" == true ]]; then
        ${EDITOR:-nvim} "$tmp" </dev/tty >/dev/tty
    else
        nvim -u NONE -c "edit $tmp" \
            -c 'set noswapfile nobackup nowritebackup wrap linebreak clipboard=unnamedplus' \
            -c 'nnoremap <buffer> q :wq<CR>' </dev/tty >/dev/tty
    fi
    cat "$tmp"
    rm -f "$tmp"
}

# --todo <id> scopes rows to notes linked to that todo; SHOW_ALL lifts the scope
format_notes() {
    jq -r --arg tid "$LINK_TODO_ID" --arg all "$SHOW_ALL" '(.notes // []) | .[] |
        select($tid == "" or $all == "1" or ((.todo_ids // []) | any(. == $tid))) |
        (if (.title // "") == "" then ((.body // "") | split("\n")[0]) else (.title) end) as $t |
        (if $tid != "" and ((.todo_ids // []) | any(. == $tid)) then "● " else "• " end) as $mark |
        "'"$COLOR_PURPLE"'\($mark)'"$COLOR_RESET"'\($t)  '"$COLOR_DIM"'[\(.id)]'"$COLOR_RESET"'"' "$TODO_LIST_PATH"
}

preview_note() {
    local line="$1"
    local id
    id=$(echo "$line" | sed 's/\x1b\[[0-9;]*m//g' | grep -oE '\[[^]]+\]$' | tr -d '[]')
    [[ -z "$id" ]] && return
    jq -r --arg id "$id" '(.notes // [])[] | select(.id == $id) |
        (.title // "(untitled)") + "\n────────────────────────────────\n" + (.body // "")' \
        "$TODO_LIST_PATH" 2>/dev/null
}
export -f preview_note

# title prompt, then body editor; returns 130 when the title prompt is cancelled
create_note() {
    local title body
    title=$(input_line "" "New note title (enter to save, esc to cancel)")
    [[ $? -eq 130 ]] && return 130
    body=$(edit_body "")
    write_list --arg id "$(new_note_id)" --arg t "$title" --arg b "$body" --arg tid "$LINK_TODO_ID" '
        .notes = ((.notes // []) + [{
            id: $id, title: $t, body: $b,
            created_at: (now | floor), updated_at: (now | floor)
        } + (if $tid == "" then {} else {todo_ids: [$tid]} end)]) |
        ._metadata.updated_at = (now | floor)'
}

NEW_ONLY=""
LINK_TODO_ID=""
SHOW_ALL=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --new) NEW_ONLY=1 ;;
        --todo) LINK_TODO_ID="$2"; shift ;;
    esac
    [[ $# -gt 0 ]] && shift
done

TODO_LABEL=""
if [[ -n "$LINK_TODO_ID" ]]; then
    TODO_LABEL=$(jq -r --arg id "$LINK_TODO_ID" '.todos[]? | select(.id == $id) | .text | split("\n")[0]' "$TODO_LIST_PATH")
    [[ -n "$TODO_LABEL" ]] || { echo "Error: todo $LINK_TODO_ID not found in $ACTIVE_LIST_NAME"; exit 1; }
fi

# --new: create one note and return to the caller (the main manager)
if [[ -n "$NEW_ONLY" ]]; then
    create_note
    exit $?
fi

while true; do
    clear
    HEADER="
 Notes — ${ACTIVE_LIST_NAME}
 n: New    e: Edit    d: Delete    y: Copy    q: Back
"
    if [[ -n "$LINK_TODO_ID" ]]; then
        SCOPE="linked only" TOGGLE="a: All notes"
        [[ -n "$SHOW_ALL" ]] && SCOPE="all notes" TOGGLE="a: Linked only"
        HEADER="
 Notes — ${ACTIVE_LIST_NAME} — todo: ${TODO_LABEL} (${SCOPE})
 n: New (linked)    l: Link/unlink    e: Edit    d: Delete    y: Copy    ${TOGGLE}    q: Back
"
    fi
    SELECTION=$(format_notes | fzf --ansi --disabled \
        --header="$HEADER" \
        --prompt="" \
        --expect=enter,n,e,d,y,a,l,q \
        --no-sort \
        --height=100% \
        --layout=reverse \
        --preview='preview_note {} | fold -s -w $FZF_PREVIEW_COLUMNS' \
        --preview-window=right:50%)

    KEY=$(echo "$SELECTION" | head -1)
    LINE=$(echo "$SELECTION" | tail -1)

    [[ "$KEY" == "q" || -z "$KEY" ]] && break

    NID=$(echo "$LINE" | sed 's/\x1b\[[0-9;]*m//g' | grep -oE '\[[^]]+\]$' | tr -d '[]')

    case "$KEY" in
        "n")
            create_note
            ;;
        "a")
            [[ -n "$LINK_TODO_ID" ]] || continue
            if [[ -n "$SHOW_ALL" ]]; then SHOW_ALL=""; else SHOW_ALL=1; fi
            ;;
        "l")
            [[ -n "$LINK_TODO_ID" && -n "$NID" ]] || continue
            write_list --arg id "$NID" --arg tid "$LINK_TODO_ID" '
                .notes |= map(if .id == $id then
                    ((.todo_ids // []) | if any(. == $tid) then map(select(. != $tid)) else . + [$tid] end) as $ids |
                    (if ($ids | length) == 0 then del(.todo_ids) else .todo_ids = $ids end) |
                    .updated_at = (now | floor)
                else . end) |
                ._metadata.updated_at = (now | floor)'
            ;;
        "e"|"enter")
            [[ -z "$NID" ]] && continue
            CUR_T=$(jq -r --arg id "$NID" '(.notes // [])[] | select(.id == $id) | .title // ""' "$TODO_LIST_PATH")
            CUR_B=$(jq -r --arg id "$NID" '(.notes // [])[] | select(.id == $id) | .body // ""' "$TODO_LIST_PATH")
            NEW_T=$(input_line "$CUR_T" "Edit title (enter to save, esc to cancel)")
            [[ $? -eq 130 ]] && continue
            NEW_B=$(edit_body "$CUR_B")
            write_list --arg id "$NID" --arg t "$NEW_T" --arg b "$NEW_B" '
                .notes |= map(if .id == $id then .title = $t | .body = $b | .updated_at = (now | floor) else . end) |
                ._metadata.updated_at = (now | floor)'
            ;;
        "y")
            [[ -z "$NID" ]] && continue
            # copy the note body (fallback to title) to the system clipboard
            COPY=$(jq -r --arg id "$NID" '(.notes // [])[] | select(.id == $id) | if (.body // "") != "" then .body else (.title // "") end' "$TODO_LIST_PATH")
            if [[ -n "$COPY" ]] && printf '%s' "$COPY" | clip; then
                clear; echo " Copied note to clipboard"; sleep 0.5
            else
                clear; echo " Nothing to copy (or no clipboard tool)"; sleep 0.8
            fi
            ;;
        "d")
            [[ -z "$NID" ]] && continue
            LBL=$(jq -r --arg id "$NID" '(.notes // [])[] | select(.id == $id) | (.title // "") | if . == "" then "(untitled)" else . end' "$TODO_LIST_PATH")
            CONFIRM=$(input_line "" "Delete note '$LBL'? type y then enter (esc to cancel)")
            [[ $? -eq 130 ]] && continue
            if [[ "$CONFIRM" == "y" ]]; then
                write_list --arg id "$NID" '
                    .notes |= map(select(.id != $id)) |
                    ._metadata.updated_at = (now | floor)'
            fi
            ;;
    esac
done
