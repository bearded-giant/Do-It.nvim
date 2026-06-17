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

format_notes() {
    jq -r '(.notes // []) | .[] |
        (if (.title // "") == "" then ((.body // "") | split("\n")[0]) else (.title) end) as $t |
        "'"$COLOR_PURPLE"'• '"$COLOR_RESET"'\($t)  '"$COLOR_DIM"'[\(.id)]'"$COLOR_RESET"'"' "$TODO_LIST_PATH"
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

while true; do
    clear
    SELECTION=$(format_notes | fzf --ansi --disabled \
        --header="
 Notes — ${ACTIVE_LIST_NAME}
 n: New    e: Edit    d: Delete    y: Copy    q: Back
" \
        --prompt="" \
        --expect=enter,n,e,d,y,q \
        --no-sort \
        --height=97% \
        --layout=reverse \
        --preview='preview_note {} | fold -s -w $FZF_PREVIEW_COLUMNS' \
        --preview-window=right:50%)

    KEY=$(echo "$SELECTION" | head -1)
    LINE=$(echo "$SELECTION" | tail -1)

    [[ "$KEY" == "q" || -z "$KEY" ]] && break

    NID=$(echo "$LINE" | sed 's/\x1b\[[0-9;]*m//g' | grep -oE '\[[^]]+\]$' | tr -d '[]')

    case "$KEY" in
        "n")
            TITLE=$(input_line "" "New note title (enter to save, esc to cancel)")
            [[ $? -eq 130 ]] && continue
            BODY=$(edit_body "")
            NEW_ID=$(new_note_id)
            write_list --arg id "$NEW_ID" --arg t "$TITLE" --arg b "$BODY" '
                .notes = ((.notes // []) + [{
                    id: $id, title: $t, body: $b,
                    created_at: (now | floor), updated_at: (now | floor)
                }]) |
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
