#!/bin/bash

# Interactive todo manager for tmux using fzf

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/get-active-list.sh"

DOIT_VERSION="$(tr -d '[:space:]' < "$SCRIPT_DIR/../../VERSION" 2>/dev/null)"

# always read from session.json, not cached env var
unset DOIT_ACTIVE_LIST
TODO_LIST_PATH="$(get_active_list_path)"
ACTIVE_LIST_NAME="$(get_active_list_name)"

# Check dependencies
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed"
    exit 1
fi

if ! command -v fzf &> /dev/null; then
    echo "Error: fzf is required but not installed"
    echo "Install with: brew install fzf"
    exit 1
fi

# Check if the list file exists
if [[ ! -f "$TODO_LIST_PATH" ]]; then
    echo "Error: Todo list '$ACTIVE_LIST_NAME' not found at $TODO_LIST_PATH"
    exit 1
fi

# ANSI color codes
COLOR_RESET=$'\e[0m'
COLOR_GREEN=$'\e[1;32m'
COLOR_RED=$'\e[1;31m'
COLOR_YELLOW=$'\e[1;33m'
COLOR_BLUE=$'\e[1;34m'
COLOR_PURPLE=$'\e[38;5;141m'
COLOR_DIM=$'\e[2m'
COLOR_HEADER=$'\e[1;36m'

priority_header_label() {
    case "$1" in
        critical)  echo "Critical" ;;
        urgent)    echo "Urgent" ;;
        important) echo "Important" ;;
        *)         echo "Default" ;;
    esac
}

# two-column help row: left field padded to a fixed width, right field appended
help_row() {
    printf "  %-42s%s\n" "$1" "$2"
}

UNDO_TYPE=""
UNDO_ID=""
UNDO_PREV_DONE=""
UNDO_PREV_IN_PROGRESS=""
UNDO_LABEL=""

snapshot_for_undo() {
    local todo_id="$1" action="$2"
    UNDO_TYPE="$action"
    UNDO_ID="$todo_id"
    UNDO_PREV_DONE=$(jq -r --arg id "$todo_id" '.todos[] | select(.id == $id) | .done' "$TODO_LIST_PATH")
    UNDO_PREV_IN_PROGRESS=$(jq -r --arg id "$todo_id" '.todos[] | select(.id == $id) | .in_progress // false' "$TODO_LIST_PATH")
    UNDO_LABEL=$(jq -r --arg id "$todo_id" '.todos[] | select(.id == $id) | .text' "$TODO_LIST_PATH")
}

# config: show completed items (default true)
SHOW_COMPLETED=$(tmux show-option -gqv @doit-show-completed)
SHOW_COMPLETED="${SHOW_COMPLETED:-true}"

# preview command for fzf - shows full todo content with line wrapping
preview_todo() {
    local line="$1"
    local todo_id=$(echo "$line" | grep -oE '\[[^]]+\]$' | tr -d '[]')
    if [[ -n "$todo_id" ]]; then
        jq -r --arg id "$todo_id" '
            .todos[] | select(.id == $id) |
            "Status: " + (if .in_progress then "In Progress" elif .done then "Done" else "Pending" end) +
            "\nPriority: " + (.priorities // "none") +
            (if .obsidian_ref then "\nObsidian:  " + (.obsidian_ref.date // "linked") else "" end) +
            "\n────────────────────────────────" +
            "\n" + .text +
            (if (.description // "") != "" then "\n\nDescription:\n" + .description else "" end)
        ' "$TODO_LIST_PATH" 2>/dev/null
    fi
}
export -f preview_todo
export TODO_LIST_PATH

# Function to display todos in a formatted way (excludes done todos)
# Format: hidden ID at end for extraction, visible: status + priority indicator + first line of text
# Shows ... indicator for multi-line items
format_todos() {
    # tracks the previous priority group so we can emit a blank line on change
    local prev_group=""
    local prev_pd_group=""
    local any_rows=""

    # text column scales with the list pane (~50% of popup; preview takes 50%)
    # read /dev/tty (popup pty) since stdout is piped into fzf, which breaks tput
    local term_cols list_w text_w hr_line
    term_cols=$(stty size </dev/tty 2>/dev/null | awk '{print $2}')
    [[ -z "$term_cols" || "$term_cols" -lt 1 ]] && term_cols=$(tput cols 2>/dev/null)
    [[ -z "$term_cols" || "$term_cols" -lt 1 ]] && term_cols=120
    list_w=$(( term_cols * 50 / 100 ))
    text_w=$(( list_w - 30 ))
    (( text_w < 40 )) && text_w=40
    (( text_w > 200 )) && text_w=200
    hr_line=$(printf '─%.0s' $(seq 1 $(( text_w + 24 ))))

    # leading blank row: visual gap under the fzf header (cursor defaults past it)
    echo ""

    # First print in-progress todos
    while IFS='|' read -r id status priority text multiline obs; do
        # blank line between distinct priority groups
        local group="${priority:-default}"
        [[ -n "$prev_group" && "$group" != "$prev_group" ]] && echo ""
        prev_group="$group"
        any_rows=1
        # Add ... for multi-line items
        suffix=""
        [[ "$multiline" == "true" ]] && suffix=" ..."
        obs_icon=""
        [[ "$obs" == "true" ]] && obs_icon="${COLOR_PURPLE} ${COLOR_RESET}"
        # Append ID at end (dimmed) for reliable extraction
        case "$priority" in
            "critical")  printf "%s%s%s! %-${text_w}s%s%s %s[%s]%s\n" "$COLOR_GREEN" "$status" "$COLOR_RED" "$text" "$suffix" "$obs_icon" "$COLOR_DIM" "$id" "$COLOR_RESET" ;;
            "urgent")    printf "%s%s%s> %-${text_w}s%s%s %s[%s]%s\n" "$COLOR_GREEN" "$status" "$COLOR_YELLOW" "$text" "$suffix" "$obs_icon" "$COLOR_DIM" "$id" "$COLOR_RESET" ;;
            "important") printf "%s%s%s* %-${text_w}s%s%s %s[%s]%s\n" "$COLOR_GREEN" "$status" "$COLOR_BLUE" "$text" "$suffix" "$obs_icon" "$COLOR_DIM" "$id" "$COLOR_RESET" ;;
            *)           printf "%s%s  %-${text_w}s%s%s %s[%s]%s\n" "$COLOR_GREEN" "$status" "$text" "$suffix" "$obs_icon" "$COLOR_DIM" "$id" "$COLOR_RESET" ;;
        esac
    done < <(jq -r --argjson tw "$text_w" '.todos |
        map(select(.in_progress == true)) |
        sort_by((if .priorities == "critical" then 0 elif .priorities == "urgent" then 1 elif .priorities == "important" then 2 else 3 end), .order_index) |
        .[] |
        (.text | split("\n")[0][0:$tw]) as $first_line |
        (.text | contains("\n")) as $multiline |
        (if .obsidian_ref then "true" else "false" end) as $obs |
        "\(.id)|\(if .in_progress then "▶" elif .done then "✓" else " " end)|\(.priorities // "")|\($first_line)|\($multiline)|\($obs)"
    ' "$TODO_LIST_PATH")

    # Then print not started todos, grouped under named priority headers
    while IFS='|' read -r id status priority text multiline obs; do
        local group="${priority:-default}"
        if [[ "$group" != "$prev_pd_group" ]]; then
            [[ -n "$any_rows" ]] && echo ""
            printf "%s%s%s\n" "$COLOR_HEADER" "$(priority_header_label "$priority")" "$COLOR_RESET"
            prev_pd_group="$group"
        fi
        prev_group="$group"
        any_rows=1
        suffix=""
        [[ "$multiline" == "true" ]] && suffix=" ..."
        obs_icon=""
        [[ "$obs" == "true" ]] && obs_icon="${COLOR_PURPLE} ${COLOR_RESET}"
        case "$priority" in
            "critical")  printf "%s%s! %-${text_w}s%s%s %s[%s]%s\n" "$COLOR_RED" "$status" "$text" "$suffix" "$obs_icon" "$COLOR_DIM" "$id" "$COLOR_RESET" ;;
            "urgent")    printf "%s%s> %-${text_w}s%s%s %s[%s]%s\n" "$COLOR_YELLOW" "$status" "$text" "$suffix" "$obs_icon" "$COLOR_DIM" "$id" "$COLOR_RESET" ;;
            "important") printf "%s%s* %-${text_w}s%s%s %s[%s]%s\n" "$COLOR_BLUE" "$status" "$text" "$suffix" "$obs_icon" "$COLOR_DIM" "$id" "$COLOR_RESET" ;;
            *)           printf "%s  %-${text_w}s%s%s %s[%s]%s\n" "$status" "$text" "$suffix" "$obs_icon" "$COLOR_DIM" "$id" "$COLOR_RESET" ;;
        esac
    done < <(jq -r --argjson tw "$text_w" '.todos |
        map(select(.done == false and .in_progress != true)) |
        sort_by((if .priorities == "critical" then 0 elif .priorities == "urgent" then 1 elif .priorities == "important" then 2 else 3 end), .order_index) |
        .[] |
        (.text | split("\n")[0][0:$tw]) as $first_line |
        (.text | contains("\n")) as $multiline |
        (if .obsidian_ref then "true" else "false" end) as $obs |
        "\(.id)|\(if .in_progress then "▶" elif .done then "✓" else " " end)|\(.priorities // "")|\($first_line)|\($multiline)|\($obs)"
    ' "$TODO_LIST_PATH")

    # Notes section (always shown) between pending and completed
    echo ""
    printf "%s%s%s\n" "$COLOR_HEADER" "Notes" "$COLOR_RESET"
    local note_rows=0
    while IFS='|' read -r nid ntitle; do
        note_rows=$((note_rows + 1))
        printf "  %s• %-${text_w}s%s %s[note_%s]%s\n" "$COLOR_PURPLE" "$ntitle" "$COLOR_RESET" "$COLOR_DIM" "$nid" "$COLOR_RESET"
    done < <(jq -r --argjson tw "$text_w" '(.notes // []) | .[] |
        (if (.title // "") == "" then ((.body // "") | split("\n")[0]) else (.title) end)[0:$tw] as $t |
        "\(.id)|\($t)"' "$TODO_LIST_PATH")
    [[ "$note_rows" -eq 0 ]] && printf "  %s(no notes)%s\n" "$COLOR_DIM" "$COLOR_RESET"

    # Finally print completed todos (if show_completed is enabled)
    if [[ "$SHOW_COMPLETED" == "true" ]]; then
        local first_done="true"
        while IFS='|' read -r id status priority text multiline obs; do
            # blank / horizontal rule / blank between notes and completed
            if [[ "$first_done" == "true" ]]; then
                first_done="false"
                printf "\n%s%s%s\n\n" "$COLOR_DIM" "$hr_line" "$COLOR_RESET"
            fi
            suffix=""
            [[ "$multiline" == "true" ]] && suffix=" ..."
            obs_icon=""
            [[ "$obs" == "true" ]] && obs_icon="${COLOR_PURPLE} ${COLOR_RESET}"
            printf "%s%s  %-${text_w}s%s%s %s[%s]%s\n" "$COLOR_DIM" "$status" "$text" "$suffix" "$obs_icon" "$COLOR_DIM" "$id" "$COLOR_RESET"
        done < <(jq -r --argjson tw "$text_w" '.todos |
            map(select(.done == true)) |
            sort_by(-(.completed_at // 0)) |
            .[] |
            (.text | split("\n")[0][0:$tw]) as $first_line |
            (.text | contains("\n")) as $multiline |
            (if .obsidian_ref then "true" else "false" end) as $obs |
            "\(.id)|✓|\(.priorities // "")|\($first_line)|\($multiline)|\($obs)"
        ' "$TODO_LIST_PATH")
    fi
}

# allow fzf reload to call this script for formatted output
if [[ "$1" == "--format" ]]; then
    format_todos
    exit 0
fi

# Priority options (default first so Enter accepts it)
PRIORITIES=("default" "critical" "urgent" "important")

# Function to select priority via fzf
select_priority() {
    local current_priority="${1:-default}"
    local header="$2"

    printf '%s\n' "${PRIORITIES[@]}" | fzf --ansi \
        --header="${header:-Select Priority} (current: $current_priority)" \
        --prompt="Priority > " \
        --height=10 \
        --layout=reverse \
        --no-sort
}

# Check for editor config: @doit-use-editor (true/false)
USE_EDITOR=$(tmux show-option -gqv "@doit-use-editor")

# note popup dimensions (configurable via @doit-note-popup-w / @doit-note-popup-h)
NOTE_POPUP_W=$(tmux show-option -gqv "@doit-note-popup-w")
NOTE_POPUP_H=$(tmux show-option -gqv "@doit-note-popup-h")
NOTE_POPUP_W="${NOTE_POPUP_W:-80}"
NOTE_POPUP_H="${NOTE_POPUP_H:-20}"
[[ "$USE_EDITOR" == "true" ]] && USE_EDITOR=true || USE_EDITOR=false

# @doit-long-desc: enable multi-line description editor (nvim --clean)
LONG_DESC=$(tmux show-option -gqv "@doit-long-desc")
[[ "$LONG_DESC" == "true" ]] && LONG_DESC=true || LONG_DESC=false

# Edit/create text input
# Usage: result=$(input_text "prefill"); status=$?
# Returns: text on success, exit 130 on cancel (Esc)
input_text() {
    local prefill="$1"
    local header="$2"
    local result=""

    if [[ "$USE_EDITOR" == true ]]; then
        # Editor mode: use $EDITOR with temp file
        local temp_file=$(mktemp /tmp/todo_edit.XXXXXX)
        [[ -n "$prefill" ]] && echo "$prefill" > "$temp_file"
        ${EDITOR:-nvim} "$temp_file"
        result=$(cat "$temp_file")
        rm -f "$temp_file"
        echo "$result"
        return 0
    else
        # Inline mode: fzf with prefilled query, Esc to cancel
        local fzf_args=(--print-query --query="$prefill"
            --height=4 --layout=reverse --no-info
            --bind 'enter:accept' --bind 'esc:abort')
        [[ -n "$header" ]] && fzf_args+=(--header "$header")
        result=$(true | fzf "${fzf_args[@]}" | head -1)
        local status=$?
        [[ $status -eq 130 ]] && return 130
        echo "$result"
        return 0
    fi
}

# Function to update todo status
update_todo() {
    local todo_id="$1"
    local action="$2"
    local priority="$3"

    case "$action" in
        "toggle")
            jq --arg id "$todo_id" '
                (.todos[] | select(.id == $id)) as $t |
                .todos |= map(
                    if .id == $id then
                        if .done then
                            .done = false | .in_progress = false | del(.completed_at)
                        elif .in_progress then
                            .in_progress = false | .done = true | .completed_at = (now | floor)
                        else
                            .in_progress = true | .done = false
                        end
                    elif ($t.done == false and $t.in_progress != true) then
                        .in_progress = false
                    else . end
                ) |
                ._metadata.updated_at = (now | floor)
            ' "$TODO_LIST_PATH" > "${TODO_LIST_PATH}.tmp" && mv "${TODO_LIST_PATH}.tmp" "$TODO_LIST_PATH"
            ;;
        "start")
            jq --arg id "$todo_id" '
                .todos |= map(
                    if .id == $id then
                        .in_progress = true |
                        .done = false
                    else
                        .in_progress = false
                    end
                ) |
                ._metadata.updated_at = (now | floor)
            ' "$TODO_LIST_PATH" > "${TODO_LIST_PATH}.tmp" && mv "${TODO_LIST_PATH}.tmp" "$TODO_LIST_PATH"
            ;;
        "stop")
            jq --arg id "$todo_id" '
                .todos |= map(
                    if .id == $id then
                        .in_progress = false
                    else . end
                ) |
                ._metadata.updated_at = (now | floor)
            ' "$TODO_LIST_PATH" > "${TODO_LIST_PATH}.tmp" && mv "${TODO_LIST_PATH}.tmp" "$TODO_LIST_PATH"
            ;;
        "complete")
            jq --arg id "$todo_id" '
                .todos |= map(
                    if .id == $id then
                        .in_progress = false |
                        .done = true |
                        .completed_at = (now | floor)
                    else . end
                ) |
                ._metadata.updated_at = (now | floor)
            ' "$TODO_LIST_PATH" > "${TODO_LIST_PATH}.tmp" && mv "${TODO_LIST_PATH}.tmp" "$TODO_LIST_PATH"
            ;;
        "revert")
            jq --arg id "$todo_id" '
                .todos |= map(
                    if .id == $id then
                        .in_progress = false |
                        .done = false |
                        del(.completed_at)
                    else . end
                ) |
                ._metadata.updated_at = (now | floor)
            ' "$TODO_LIST_PATH" > "${TODO_LIST_PATH}.tmp" && mv "${TODO_LIST_PATH}.tmp" "$TODO_LIST_PATH"
            ;;
        "priority")
            local new_priority="$priority"
            if [[ "$new_priority" == "default" ]]; then
                # remove priority field
                jq --arg id "$todo_id" '
                    .todos |= map(
                        if .id == $id then
                            del(.priorities)
                        else . end
                    ) |
                    ._metadata.updated_at = (now | floor)
                ' "$TODO_LIST_PATH" > "${TODO_LIST_PATH}.tmp" && mv "${TODO_LIST_PATH}.tmp" "$TODO_LIST_PATH"
            else
                jq --arg id "$todo_id" --arg priority "$new_priority" '
                    .todos |= map(
                        if .id == $id then
                            .priorities = $priority
                        else . end
                    ) |
                    ._metadata.updated_at = (now | floor)
                ' "$TODO_LIST_PATH" > "${TODO_LIST_PATH}.tmp" && mv "${TODO_LIST_PATH}.tmp" "$TODO_LIST_PATH"
            fi
            ;;
        "move_up")
            # swap order_index with the todo above (lower order_index among non-done items)
            jq --arg id "$todo_id" '
                # get current todo order_index
                (.todos[] | select(.id == $id) | .order_index) as $current_order |
                # find the todo just above (highest order_index less than current, excluding done)
                ([.todos[] | select(.done == false and .order_index < $current_order)] | max_by(.order_index)) as $above |
                if $above then
                    .todos |= map(
                        if .id == $id then
                            .order_index = $above.order_index
                        elif .id == $above.id then
                            .order_index = $current_order
                        else . end
                    )
                else . end |
                ._metadata.updated_at = (now | floor)
            ' "$TODO_LIST_PATH" > "${TODO_LIST_PATH}.tmp" && mv "${TODO_LIST_PATH}.tmp" "$TODO_LIST_PATH"
            ;;
        "move_down")
            # swap order_index with the todo below (higher order_index among non-done items)
            jq --arg id "$todo_id" '
                # get current todo order_index
                (.todos[] | select(.id == $id) | .order_index) as $current_order |
                # find the todo just below (lowest order_index greater than current, excluding done)
                ([.todos[] | select(.done == false and .order_index > $current_order)] | min_by(.order_index)) as $below |
                if $below then
                    .todos |= map(
                        if .id == $id then
                            .order_index = $below.order_index
                        elif .id == $below.id then
                            .order_index = $current_order
                        else . end
                    )
                else . end |
                ._metadata.updated_at = (now | floor)
            ' "$TODO_LIST_PATH" > "${TODO_LIST_PATH}.tmp" && mv "${TODO_LIST_PATH}.tmp" "$TODO_LIST_PATH"
            ;;
        "delete")
            jq --arg id "$todo_id" '
                .todos |= map(select(.id != $id)) |
                ._metadata.updated_at = (now | floor)
            ' "$TODO_LIST_PATH" > "${TODO_LIST_PATH}.tmp" && mv "${TODO_LIST_PATH}.tmp" "$TODO_LIST_PATH"
            ;;
    esac
}

# Main interactive loop
while true; do
    clear
    # Show todos and prompt for selection
    done_count=$(jq '[.todos[] | select(.done == true)] | length' "$TODO_LIST_PATH" 2>/dev/null || echo 0)
    LIST=$(format_todos)
    # park the cursor on a just-created/edited todo when one is queued;
    # default past the leading blank row to the first real line
    START_BIND=(--bind "start:pos(2)")
    if [[ -n "$CURSOR_TARGET" ]]; then
        TARGET_LN=$(printf '%s\n' "$LIST" | sed 's/\x1b\[[0-9;]*m//g' | grep -nF "[$CURSOR_TARGET]" | head -1 | cut -d: -f1)
        [[ -n "$TARGET_LN" ]] && START_BIND=(--bind "start:pos($TARGET_LN)")
        CURSOR_TARGET=""
    fi
    SELECTION=$(printf '%s\n' "$LIST" | fzf --ansi --disabled \
        "${START_BIND[@]}" \
        --header=" Todo Manager - ${ACTIVE_LIST_NAME}${DOIT_VERSION:+  v$DOIT_VERSION}  (done: $done_count)   ·   [?] help" \
        --prompt="" \
        --expect=enter,s,x,X,n,r,N,P,d,D,e,u,l,L,m,y,p,B,O,q,?,/,g \
        --bind "K:execute-silent($SCRIPT_DIR/todo-move.sh up {})+reload($SCRIPT_DIR/todo-interactive.sh --format)+up" \
        --bind "ctrl-up:execute-silent($SCRIPT_DIR/todo-move.sh up {})+reload($SCRIPT_DIR/todo-interactive.sh --format)+up" \
        --bind "J:execute-silent($SCRIPT_DIR/todo-move.sh down {})+reload($SCRIPT_DIR/todo-interactive.sh --format)+down" \
        --bind "ctrl-down:execute-silent($SCRIPT_DIR/todo-move.sh down {})+reload($SCRIPT_DIR/todo-interactive.sh --format)+down" \
        --bind "[:transform:$SCRIPT_DIR/section-jump.sh down {n}" \
        --bind "]:transform:$SCRIPT_DIR/section-jump.sh up {n}" \
        --no-sort \
        --height=97% \
        --layout=reverse \
        --preview='preview_todo {} | fold -s -w $FZF_PREVIEW_COLUMNS' \
        --preview-window=right:50%)

    # Parse the selection
    KEY=$(echo "$SELECTION" | head -1)
    TODO_LINE=$(echo "$SELECTION" | tail -1)

    # Exit on q or escape
    if [[ "$KEY" == "q" ]] || [[ -z "$TODO_LINE" ]]; then
        break
    fi

    # Extract the todo ID from the bracketed ID at end of line [id]
    # Strip ANSI codes first since COLOR_RESET follows the ID
    TODO_ID=$(echo "$TODO_LINE" | sed 's/\x1b\[[0-9;]*m//g' | grep -oE '\[[^]]+\]$' | tr -d '[]')

    # List-scoped note rows are tagged [note_<id>]; route them to the notes modal
    NOTE_ID=""
    if [[ "$TODO_ID" == note_* ]]; then
        NOTE_ID="${TODO_ID#note_}"
        TODO_ID=""
    fi
    if [[ "$KEY" == "g" ]] || { [[ -n "$NOTE_ID" ]] && [[ "$KEY" =~ ^(enter|e|d|n)$ ]]; }; then
        "$SCRIPT_DIR/todo-notes.sh"
        continue
    fi

    # Perform action based on key
    case "$KEY" in
        "enter"|"")
            # view item + edit notes in nvim
            if [[ -n "$TODO_ID" ]]; then
                VIEW_TMP=$(mktemp /tmp/todo_view.XXXXXX)
                TODO_OBJ=$(jq -r --arg id "$TODO_ID" '.todos[] | select(.id == $id)' "$TODO_LIST_PATH")
                VIEW_TEXT=$(echo "$TODO_OBJ" | jq -r '.text // ""')
                VIEW_DESC=$(echo "$TODO_OBJ" | jq -r '.description // ""')
                VIEW_PRIORITY=$(echo "$TODO_OBJ" | jq -r '.priorities // "default"')
                VIEW_STATUS="pending"
                echo "$TODO_OBJ" | jq -e '.in_progress == true' &>/dev/null && VIEW_STATUS="in-progress"
                echo "$TODO_OBJ" | jq -e '.done == true' &>/dev/null && VIEW_STATUS="done"

                NOTES_MARKER="── notes (editable below) ──────────────"
                {
                    echo "[$VIEW_STATUS] [$VIEW_PRIORITY]"
                    echo "$VIEW_TEXT"
                    echo "$NOTES_MARKER"
                    [[ -n "$VIEW_DESC" ]] && echo "$VIEW_DESC"
                } > "$VIEW_TMP"

                HEADER_LINES=3
                nvim -u NONE -c "edit $VIEW_TMP" \
                    -c 'set noswapfile nobackup nowritebackup wrap linebreak clipboard=unnamedplus' \
                    -c "normal! ${HEADER_LINES}jG" \
                    -c 'nnoremap <buffer> q :wq<CR>'

                NEW_DESC=$(tail -n +$((HEADER_LINES + 1)) "$VIEW_TMP")
                rm -f "$VIEW_TMP"
                jq --arg id "$TODO_ID" --arg desc "$NEW_DESC" '
                    .todos |= map(if .id == $id then .description = $desc else . end) |
                    ._metadata.updated_at = (now | floor)
                ' "$TODO_LIST_PATH" > "${TODO_LIST_PATH}.tmp" && mv "${TODO_LIST_PATH}.tmp" "$TODO_LIST_PATH"
            fi
            ;;
        "s")
            if [[ -n "$TODO_ID" ]]; then
                snapshot_for_undo "$TODO_ID" "start"
                update_todo "$TODO_ID" "start"
                echo "Started: $UNDO_LABEL (u to undo)"
                sleep 0.5
            fi
            ;;
        "x")
            if [[ -n "$TODO_ID" ]]; then
                snapshot_for_undo "$TODO_ID" "complete"
                update_todo "$TODO_ID" "complete"
                echo "Done: $UNDO_LABEL (u to undo)"
                sleep 0.5
            fi
            ;;
        "X")
            if [[ -n "$TODO_ID" ]]; then
                snapshot_for_undo "$TODO_ID" "revert"
                update_todo "$TODO_ID" "revert"
                echo "Reverted to pending: $UNDO_LABEL (u to undo)"
                sleep 0.5
            fi
            ;;
        "N")
            # add/edit description on a todo
            if [[ -n "$TODO_ID" ]]; then
                CURRENT_DESC=$(jq -r --arg id "$TODO_ID" '.todos[] | select(.id == $id) | .description // ""' "$TODO_LIST_PATH")
                if [[ "$LONG_DESC" == true ]]; then
                    DESC_TMP=$(mktemp /tmp/todo_desc.XXXXXX)
                    [[ -n "$CURRENT_DESC" ]] && printf '%s' "$CURRENT_DESC" > "$DESC_TMP"
                    nvim -u NONE -c "edit $DESC_TMP" -c 'set noswapfile nobackup nowritebackup wrap linebreak clipboard=unnamedplus' -c 'nnoremap <buffer> q :wq<CR>'
                    NEW_DESC=$(cat "$DESC_TMP")
                    rm -f "$DESC_TMP"
                else
                    NEW_DESC=$(input_text "$CURRENT_DESC" "Description (enter to save, esc to cancel)")
                    [[ $? -eq 130 ]] && continue
                fi
                jq --arg id "$TODO_ID" --arg desc "$NEW_DESC" '
                    .todos |= map(if .id == $id then .description = $desc else . end) |
                    ._metadata.updated_at = (now | floor)
                ' "$TODO_LIST_PATH" > "${TODO_LIST_PATH}.tmp" && mv "${TODO_LIST_PATH}.tmp" "$TODO_LIST_PATH"
            fi
            ;;
        "P")
            if [[ -n "$TODO_ID" ]]; then
                # get current priority
                CURRENT_PRIORITY=$(jq -r --arg id "$TODO_ID" '.todos[] | select(.id == $id) | .priorities // "default"' "$TODO_LIST_PATH")
                NEW_PRIORITY=$(select_priority "$CURRENT_PRIORITY" "Set Priority")
                if [[ -n "$NEW_PRIORITY" ]]; then
                    update_todo "$TODO_ID" "priority" "$NEW_PRIORITY"
                    echo "Priority set to: $NEW_PRIORITY"
                    sleep 0.5
                fi
            fi
            ;;
        # K/J/ctrl-up/ctrl-down handled via fzf --bind (in-place reload, no fzf restart)
        "e")
            # Edit todo text
            if [[ -n "$TODO_ID" ]]; then
                CURRENT_TEXT=$(jq -r --arg id "$TODO_ID" '.todos[] | select(.id == $id) | .text' "$TODO_LIST_PATH")

                echo ""
                echo " Edit (Enter=save, Esc=cancel)"
                echo ""

                NEW_TEXT=$(input_text "$CURRENT_TEXT")
                INPUT_STATUS=$?

                if [[ $INPUT_STATUS -eq 130 ]]; then
                    echo "Cancelled"
                    sleep 0.3
                elif [[ -z "$NEW_TEXT" ]]; then
                    echo "Keeping original"
                    sleep 0.3
                elif [[ "$NEW_TEXT" != "$CURRENT_TEXT" ]]; then
                    jq --arg id "$TODO_ID" --arg text "$NEW_TEXT" '
                        .todos |= map(if .id == $id then .text = $text else . end) |
                        ._metadata.updated_at = (now | floor)
                    ' "$TODO_LIST_PATH" > "${TODO_LIST_PATH}.tmp" && mv "${TODO_LIST_PATH}.tmp" "$TODO_LIST_PATH"
                    echo "Updated"
                    sleep 0.3
                else
                    echo "No changes"
                    sleep 0.3
                fi
            fi
            ;;
        "d")
            # Soft delete - move to deleted_todos for undo
            if [[ -n "$TODO_ID" ]]; then
                TODO_TEXT=$(jq -r --arg id "$TODO_ID" '.todos[] | select(.id == $id) | .text' "$TODO_LIST_PATH")
                echo -n "Delete '$TODO_TEXT'? (y/N): "
                read -n 1 -r CONFIRM
                echo
                if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
                    UNDO_TYPE="delete"
                    UNDO_ID="$TODO_ID"
                    UNDO_LABEL="$TODO_TEXT"
                    jq --arg id "$TODO_ID" '
                        (.todos[] | select(.id == $id)) as $deleted |
                        .todos |= map(select(.id != $id)) |
                        ._metadata.deleted_todos = ([$deleted] + (._metadata.deleted_todos // []))[0:10] |
                        ._metadata.updated_at = (now | floor)
                    ' "$TODO_LIST_PATH" > "${TODO_LIST_PATH}.tmp" && mv "${TODO_LIST_PATH}.tmp" "$TODO_LIST_PATH"
                    echo "Deleted (u to undo)"
                    sleep 0.5
                fi
            fi
            ;;
        "D")
            # Batch delete all completed todos
            COMPLETED_COUNT=$(jq '[.todos[] | select(.done == true)] | length' "$TODO_LIST_PATH")
            if [[ "$COMPLETED_COUNT" -gt 0 ]]; then
                echo -n "Delete $COMPLETED_COUNT completed todos? (y/N): "
                read -n 1 -r CONFIRM
                echo
                if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
                    jq '
                        [.todos[] | select(.done == true)] as $deleted |
                        .todos |= map(select(.done == false)) |
                        ._metadata.deleted_todos = ($deleted + (._metadata.deleted_todos // []))[0:10] |
                        ._metadata.updated_at = (now | floor)
                    ' "$TODO_LIST_PATH" > "${TODO_LIST_PATH}.tmp" && mv "${TODO_LIST_PATH}.tmp" "$TODO_LIST_PATH"
                    echo "Deleted $COMPLETED_COUNT completed todos"
                    sleep 0.5
                fi
            else
                echo "No completed todos to delete"
                sleep 0.5
            fi
            ;;
        "u")
            if [[ -z "$UNDO_TYPE" ]]; then
                echo "Nothing to undo"
                sleep 0.5
            elif [[ "$UNDO_TYPE" == "delete" ]]; then
                HAS_DELETED=$(jq -r '._metadata.deleted_todos[0].id // empty' "$TODO_LIST_PATH")
                if [[ -n "$HAS_DELETED" ]]; then
                    RESTORED_TEXT=$(jq -r '._metadata.deleted_todos[0].text' "$TODO_LIST_PATH")
                    jq '
                        ._metadata.deleted_todos[0] as $restore |
                        .todos += [$restore] |
                        ._metadata.deleted_todos = ._metadata.deleted_todos[1:] |
                        ._metadata.updated_at = (now | floor)
                    ' "$TODO_LIST_PATH" > "${TODO_LIST_PATH}.tmp" && mv "${TODO_LIST_PATH}.tmp" "$TODO_LIST_PATH"
                    echo "Restored: $RESTORED_TEXT"
                fi
                UNDO_TYPE=""
                sleep 0.5
            else
                jq --arg id "$UNDO_ID" --argjson done "$UNDO_PREV_DONE" --argjson ip "$UNDO_PREV_IN_PROGRESS" '
                    .todos |= map(
                        if .id == $id then
                            .done = $done | .in_progress = $ip |
                            if $done then . else del(.completed_at) end
                        else . end
                    ) |
                    ._metadata.updated_at = (now | floor)
                ' "$TODO_LIST_PATH" > "${TODO_LIST_PATH}.tmp" && mv "${TODO_LIST_PATH}.tmp" "$TODO_LIST_PATH"
                echo "Undid $UNDO_TYPE: $UNDO_LABEL"
                UNDO_TYPE=""
                sleep 0.5
            fi
            ;;
        "l")
            # Open list switch
            "$SCRIPT_DIR/todo-list-switch.sh"
            # Clear cached env var so we read fresh from session.json
            unset DOIT_ACTIVE_LIST
            # Reload list path after switch
            TODO_LIST_PATH="$(get_active_list_path)"
            ACTIVE_LIST_NAME="$(get_active_list_name)"
            export TODO_LIST_PATH
            ;;
        "L")
            # Open list manager
            "$SCRIPT_DIR/todo-list-manager.sh"
            # Clear cached env var so we read fresh from session.json
            unset DOIT_ACTIVE_LIST
            # Reload list path after switch
            TODO_LIST_PATH="$(get_active_list_path)"
            ACTIVE_LIST_NAME="$(get_active_list_name)"
            export TODO_LIST_PATH
            ;;
        "B")
            "$SCRIPT_DIR/todo-backup.sh"
            sleep 1
            ;;
        "m")
            # Move todo to another list
            if [[ -n "$TODO_ID" ]]; then
                # Get available lists except current
                TARGET_LIST=$(get_available_lists | grep -v "^${ACTIVE_LIST_NAME}$" | \
                    fzf --ansi \
                        --header="Move to list (from: $ACTIVE_LIST_NAME)" \
                        --prompt="Target > " \
                        --height=40% \
                        --layout=reverse)

                if [[ -n "$TARGET_LIST" ]]; then
                    TARGET_PATH="$LISTS_DIR/${TARGET_LIST}.json"

                    # Get the todo object
                    TODO_OBJ=$(jq --arg id "$TODO_ID" '.todos[] | select(.id == $id)' "$TODO_LIST_PATH")

                    if [[ -n "$TODO_OBJ" ]]; then
                        # Remove from current list
                        jq --arg id "$TODO_ID" '
                            .todos |= map(select(.id != $id)) |
                            ._metadata.updated_at = (now | floor)
                        ' "$TODO_LIST_PATH" > "${TODO_LIST_PATH}.tmp" && mv "${TODO_LIST_PATH}.tmp" "$TODO_LIST_PATH"

                        # Add to target list
                        jq --argjson todo "$TODO_OBJ" '
                            .todos += [$todo] |
                            ._metadata.updated_at = (now | floor)
                        ' "$TARGET_PATH" > "${TARGET_PATH}.tmp" && mv "${TARGET_PATH}.tmp" "$TARGET_PATH"

                        TODO_TEXT=$(echo "$TODO_OBJ" | jq -r '.text | split("\n")[0][0:30]')
                        echo "Moved to $TARGET_LIST: $TODO_TEXT"
                        sleep 0.5
                    fi
                fi
            fi
            ;;
        "y")
            # copy todo text to system clipboard
            if [[ -n "$TODO_ID" ]]; then
                COPY_TEXT=$(jq -r --arg id "$TODO_ID" '.todos[] | select(.id == $id) | .text' "$TODO_LIST_PATH" 2>/dev/null)
                if [[ -n "$COPY_TEXT" ]]; then
                    if command -v pbcopy &>/dev/null; then
                        printf '%s' "$COPY_TEXT" | pbcopy
                    elif command -v xclip &>/dev/null; then
                        printf '%s' "$COPY_TEXT" | xclip -selection clipboard
                    elif command -v xsel &>/dev/null; then
                        printf '%s' "$COPY_TEXT" | xsel --clipboard
                    else
                        echo "No clipboard tool found (pbcopy/xclip/xsel)"
                        sleep 1
                        continue
                    fi
                    echo "Copied to clipboard"
                    sleep 0.5
                fi
            fi
            ;;
        "O")
            # send todo to obsidian daily note
            if [[ -n "$TODO_ID" ]]; then
                # check if already linked
                HAS_REF=$(jq -r --arg id "$TODO_ID" '.todos[] | select(.id == $id) | .obsidian_ref // empty' "$TODO_LIST_PATH")
                if [[ -n "$HAS_REF" ]]; then
                    echo "Already linked to daily note"
                    sleep 1
                    continue
                fi

                VAULT_PATH=$(tmux show-option -gqv "@doit-obsidian-vault")
                VAULT_PATH="${VAULT_PATH:-$HOME/Recharge-Notes}"
                SECTION_MARKER=$(tmux show-option -gqv "@doit-obsidian-section")
                SECTION_MARKER="${SECTION_MARKER:-## TODO}"
                DAILY_TEMPLATE=$(tmux show-option -gqv "@doit-obsidian-daily-path")
                DAILY_TEMPLATE="${DAILY_TEMPLATE:-daily/%Y-%m-%d.md}"
                LOOKBACK_DAYS=$(tmux show-option -gqv "@doit-obsidian-lookback")
                LOOKBACK_DAYS="${LOOKBACK_DAYS:-7}"
                TODAY=$(date +%Y-%m-%d)
                DAILY_PATH="$VAULT_PATH/$(date +"$DAILY_TEMPLATE")"

                if [[ ! -f "$DAILY_PATH" && "$LOOKBACK_DAYS" -gt 0 ]]; then
                    for i in $(seq 1 "$LOOKBACK_DAYS"); do
                        PAST_PATH="$VAULT_PATH/$(date -v-${i}d +"$DAILY_TEMPLATE" 2>/dev/null || date -d "-${i} days" +"$DAILY_TEMPLATE")"
                        if [[ -f "$PAST_PATH" ]]; then
                            DAILY_PATH="$PAST_PATH"
                            break
                        fi
                    done
                fi

                if [[ ! -f "$DAILY_PATH" ]]; then
                    echo "No daily note found (checked $((LOOKBACK_DAYS + 1)) days): $DAILY_PATH"
                    sleep 1
                    continue
                fi

                TODO_TEXT=$(jq -r --arg id "$TODO_ID" '.todos[] | select(.id == $id) | .text' "$TODO_LIST_PATH")
                NEW_LINE="- [ ] - $TODO_TEXT <!-- doit:$TODO_ID -->"

                # single-pass: insert right after section heading
                awk -v line="$NEW_LINE" -v marker="$SECTION_MARKER" '
                    index($0, marker) == 1 { print; print line; inserted=1; next }
                    { print }
                    END { if (!inserted) print "ERROR: no " marker " section" > "/dev/stderr" }
                ' "$DAILY_PATH" > "${DAILY_PATH}.tmp"

                if ! grep -qF "$SECTION_MARKER" "${DAILY_PATH}.tmp"; then
                    echo "No $SECTION_MARKER section found in daily note"
                    rm -f "${DAILY_PATH}.tmp"
                    sleep 1
                    continue
                fi
                mv "${DAILY_PATH}.tmp" "$DAILY_PATH"

                # set obsidian_ref (lnum 0 — nvim refresh_buffer_refs derives real value)
                jq --arg id "$TODO_ID" --arg date "$TODAY" --arg file "$DAILY_PATH" '
                    .todos |= map(
                        if .id == $id then
                            .obsidian_ref = { file: $file, date: $date, lnum: 0 }
                        else . end
                    ) |
                    ._metadata.updated_at = (now | floor)
                ' "$TODO_LIST_PATH" > "${TODO_LIST_PATH}.tmp" && mv "${TODO_LIST_PATH}.tmp" "$TODO_LIST_PATH"

                SHORT=$(echo "$TODO_TEXT" | head -1 | cut -c1-40)
                echo "Sent to daily: $SHORT"
                sleep 1
            fi
            ;;
        "p")
            # paste from clipboard as new todo
            PASTED=""
            if command -v pbpaste &>/dev/null; then
                PASTED=$(pbpaste)
            elif command -v xclip &>/dev/null; then
                PASTED=$(xclip -selection clipboard -o)
            elif command -v xsel &>/dev/null; then
                PASTED=$(xsel --clipboard)
            fi

            if [[ -z "$PASTED" ]]; then
                echo "Clipboard is empty"
                sleep 0.5
                continue
            fi

            # show preview and confirm
            echo ""
            PREVIEW=$(echo "$PASTED" | head -3)
            LINE_COUNT=$(echo "$PASTED" | wc -l | tr -d ' ')
            echo " Paste from clipboard ($LINE_COUNT lines):"
            echo " $PREVIEW"
            [[ "$LINE_COUNT" -gt 3 ]] && echo " ..."
            echo ""
            echo -n " Create todo from clipboard? (Y/n): "
            read -n 1 -r CONFIRM
            echo

            if [[ "$CONFIRM" =~ ^[Nn]$ ]]; then
                echo "Cancelled"
                sleep 0.3
                continue
            fi

            TODO_TEXT="$PASTED"

            SELECTED_PRIORITY=$(select_priority "default" "Select Priority (Enter for default)")

            TODO_ID="$(date +%s)_$(( RANDOM * RANDOM % 9999999 ))"
            MAX_ORDER=$(jq '.todos | map(.order_index) | max // 0' "$TODO_LIST_PATH")
            NEW_ORDER=$((MAX_ORDER + 1))

            if [[ -n "$SELECTED_PRIORITY" && "$SELECTED_PRIORITY" != "default" ]]; then
                jq --arg id "$TODO_ID" \
                   --arg text "$TODO_TEXT" \
                   --arg order "$NEW_ORDER" \
                   --arg priority "$SELECTED_PRIORITY" \
                   '.todos += [{
                      id: $id,
                      text: $text,
                      done: false,
                      in_progress: false,
                      order_index: ($order | tonumber),
                      created_at: (now | floor),
                      priorities: $priority
                   }] |
                   ._metadata.updated_at = (now | floor)' \
                   "$TODO_LIST_PATH" > "${TODO_LIST_PATH}.tmp" && mv "${TODO_LIST_PATH}.tmp" "$TODO_LIST_PATH"
            else
                jq --arg id "$TODO_ID" \
                   --arg text "$TODO_TEXT" \
                   --arg order "$NEW_ORDER" \
                   '.todos += [{
                      id: $id,
                      text: $text,
                      done: false,
                      in_progress: false,
                      order_index: ($order | tonumber),
                      created_at: (now | floor)
                   }] |
                   ._metadata.updated_at = (now | floor)' \
                   "$TODO_LIST_PATH" > "${TODO_LIST_PATH}.tmp" && mv "${TODO_LIST_PATH}.tmp" "$TODO_LIST_PATH"
            fi

            if [[ $? -eq 0 ]]; then
                # park cursor on the pasted todo when the list redraws
                CURSOR_TARGET="$TODO_ID"
                SHORT=$(echo "$TODO_TEXT" | head -1 | cut -c1-40)
                echo "✓ Created from clipboard: $SHORT"
                sleep 0.5
            fi
            ;;
        "n")
            # New todo
            echo ""
            echo " New Todo (Enter=save, Esc=cancel)"
            echo ""

            TODO_TEXT=$(input_text "")
            INPUT_STATUS=$?

            if [[ $INPUT_STATUS -eq 130 ]]; then
                echo "Cancelled"
                sleep 0.3
            elif [[ -n "$TODO_TEXT" ]]; then
                # Select priority
                echo ""
                SELECTED_PRIORITY=$(select_priority "default" "Select Priority (Enter for default)")

                # Generate unique ID
                TODO_ID="$(date +%s)_$(( RANDOM * RANDOM % 9999999 ))"

                # Get the highest order_index
                MAX_ORDER=$(jq '.todos | map(.order_index) | max // 0' "$TODO_LIST_PATH")
                NEW_ORDER=$((MAX_ORDER + 1))

                # Add the new todo (with or without priority)
                if [[ -n "$SELECTED_PRIORITY" && "$SELECTED_PRIORITY" != "default" ]]; then
                    jq --arg id "$TODO_ID" \
                       --arg text "$TODO_TEXT" \
                       --arg order "$NEW_ORDER" \
                       --arg priority "$SELECTED_PRIORITY" \
                       '.todos += [{
                          id: $id,
                          text: $text,
                          done: false,
                          in_progress: false,
                          order_index: ($order | tonumber),
                          created_at: (now | floor),
                          priorities: $priority
                       }] |
                       ._metadata.updated_at = (now | floor)' \
                       "$TODO_LIST_PATH" > "${TODO_LIST_PATH}.tmp" && mv "${TODO_LIST_PATH}.tmp" "$TODO_LIST_PATH"
                else
                    jq --arg id "$TODO_ID" \
                       --arg text "$TODO_TEXT" \
                       --arg order "$NEW_ORDER" \
                       '.todos += [{
                          id: $id,
                          text: $text,
                          done: false,
                          in_progress: false,
                          order_index: ($order | tonumber),
                          created_at: (now | floor)
                       }] |
                       ._metadata.updated_at = (now | floor)' \
                       "$TODO_LIST_PATH" > "${TODO_LIST_PATH}.tmp" && mv "${TODO_LIST_PATH}.tmp" "$TODO_LIST_PATH"
                fi

                if [[ $? -eq 0 ]]; then
                    # park cursor on the new todo when the list redraws
                    CURSOR_TARGET="$TODO_ID"
                    echo ""
                    if [[ -n "$SELECTED_PRIORITY" && "$SELECTED_PRIORITY" != "default" ]]; then
                        echo "Created [$SELECTED_PRIORITY]: $TODO_TEXT"
                    else
                        echo "Created: $TODO_TEXT"
                    fi

                    # Ask if should mark as in-progress
                    echo ""
                    # flush any buffered stdin from prior fzf interactions
                    while read -r -t 0 2>/dev/null; do read -r -n 256 -t 0.1 2>/dev/null; done
                    echo -n "Mark as in-progress? (y/N): "
                    read -n 1 -r MARK_PROGRESS
                    echo

                    if [[ "$MARK_PROGRESS" =~ ^[Yy]$ ]]; then
                        jq --arg id "$TODO_ID" '
                            .todos |= map(
                                if .id == $id then
                                    .in_progress = true
                                else
                                    .in_progress = false
                                end
                            ) |
                            ._metadata.updated_at = (now | floor)
                        ' "$TODO_LIST_PATH" > "${TODO_LIST_PATH}.tmp" && mv "${TODO_LIST_PATH}.tmp" "$TODO_LIST_PATH"
                        echo "Marked as in-progress"
                    fi
                else
                    echo "Error: Failed to create todo"
                fi
                sleep 2
            else
                echo "No text entered"
                sleep 0.5
            fi
            ;;
        "/")
            # search mode: re-launch fzf with filtering enabled
            SEARCH_RESULT=$(format_todos | fzf --ansi \
                --header=" Type to filter, Enter to select, Esc to cancel" \
                --prompt="/ " \
                --no-sort \
                --height=80% \
                --layout=reverse \
                --preview='preview_todo {} | fold -s -w $FZF_PREVIEW_COLUMNS' \
                --preview-window=right:50%)

            if [[ -n "$SEARCH_RESULT" ]]; then
                SEARCH_ID=$(echo "$SEARCH_RESULT" | sed 's/\x1b\[[0-9;]*m//g' | grep -oE '\[[^]]+\]$' | tr -d '[]')
                if [[ -n "$SEARCH_ID" ]]; then
                    update_todo "$SEARCH_ID" "toggle"
                    echo "Toggled: $(jq -r --arg id "$SEARCH_ID" '.todos[] | select(.id == $id) | .text' "$TODO_LIST_PATH")"
                    sleep 0.5
                fi
            fi
            ;;
        "r")
            echo "Refreshed"
            sleep 0.3
            ;;
        "?")
            # Help: two columns, functional categories, no scroll
            clear
            hr=$(printf '─%.0s' $(seq 1 76))
            printf "\n  %sTodo Manager — Help%s\n" "$COLOR_HEADER" "$COLOR_RESET"
            printf "  %s\n\n" "$hr"
            help_row "NAVIGATION"                       "EDIT"
            help_row "  j / k    Move up / down"         "  n      New todo"
            help_row "  K / J    Reorder up / down"      "  p      Paste new (clipboard)"
            help_row "  [ / ]    Jump section down / up" "  e      Edit todo text"
            help_row "STATUS"                            "  P      Set priority"
            help_row "  s        Start (in-progress)"    "  d      Delete todo"
            help_row "  x        Complete (done)"        "  D      Clear all completed"
            help_row "  X        Revert to pending"      "  u      Undo last delete"
            printf "\n"
            help_row "NOTES"                             "ORGANIZE"
            help_row "  N        Edit note (description)" "  m      Move todo to list"
            help_row "  g        List notes (modal)"      "  l      Switch list"
            help_row ""                                  "  L      List manager"
            help_row "VIEW / MISC"                       "  /      Search / filter"
            help_row "  Enter    View detail (nvim)"      ""
            help_row "  y        Copy text"              "OBSIDIAN"
            help_row "  ?        This help"              "  O      Send to daily note"
            help_row "  q        Quit"                   ""
            printf "\n  %s\n" "$hr"
            printf "  Press any key to return...\n"
            read -n 1 -s
            ;;
    esac
done

echo "Exiting todo manager"