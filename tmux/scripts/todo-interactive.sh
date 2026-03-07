#!/bin/bash

# Interactive todo manager for tmux using fzf

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/get-active-list.sh"

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
    # First print in-progress todos
    jq -r '.todos |
        map(select(.in_progress == true)) |
        sort_by((if .priorities == "critical" then 0 elif .priorities == "urgent" then 1 elif .priorities == "important" then 2 else 3 end), .order_index) |
        .[] |
        (.text | split("\n")[0][0:55]) as $first_line |
        (.text | contains("\n")) as $multiline |
        (if .obsidian_ref then "true" else "false" end) as $obs |
        "\(.id)|\(if .in_progress then "▶" elif .done then "✓" else " " end)|\(.priorities // "")|\($first_line)|\($multiline)|\($obs)"
    ' "$TODO_LIST_PATH" |
    while IFS='|' read -r id status priority text multiline obs; do
        # Add ... for multi-line items
        suffix=""
        [[ "$multiline" == "true" ]] && suffix=" ..."
        obs_icon=""
        [[ "$obs" == "true" ]] && obs_icon="${COLOR_PURPLE} ${COLOR_RESET}"
        # Append ID at end (dimmed) for reliable extraction
        case "$priority" in
            "critical")  printf "%s%s%s! %-55s%s%s %s[%s]%s\n" "$COLOR_GREEN" "$status" "$COLOR_RED" "$text" "$suffix" "$obs_icon" "$COLOR_DIM" "$id" "$COLOR_RESET" ;;
            "urgent")    printf "%s%s%s> %-55s%s%s %s[%s]%s\n" "$COLOR_GREEN" "$status" "$COLOR_YELLOW" "$text" "$suffix" "$obs_icon" "$COLOR_DIM" "$id" "$COLOR_RESET" ;;
            "important") printf "%s%s%s* %-55s%s%s %s[%s]%s\n" "$COLOR_GREEN" "$status" "$COLOR_BLUE" "$text" "$suffix" "$obs_icon" "$COLOR_DIM" "$id" "$COLOR_RESET" ;;
            *)           printf "%s%s  %-55s%s%s %s[%s]%s\n" "$COLOR_GREEN" "$status" "$text" "$suffix" "$obs_icon" "$COLOR_DIM" "$id" "$COLOR_RESET" ;;
        esac
    done

    # Then print not started todos
    jq -r '.todos |
        map(select(.done == false and .in_progress != true)) |
        sort_by((if .priorities == "critical" then 0 elif .priorities == "urgent" then 1 elif .priorities == "important" then 2 else 3 end), .order_index) |
        .[] |
        (.text | split("\n")[0][0:55]) as $first_line |
        (.text | contains("\n")) as $multiline |
        (if .obsidian_ref then "true" else "false" end) as $obs |
        "\(.id)|\(if .in_progress then "▶" elif .done then "✓" else " " end)|\(.priorities // "")|\($first_line)|\($multiline)|\($obs)"
    ' "$TODO_LIST_PATH" |
    while IFS='|' read -r id status priority text multiline obs; do
        suffix=""
        [[ "$multiline" == "true" ]] && suffix=" ..."
        obs_icon=""
        [[ "$obs" == "true" ]] && obs_icon="${COLOR_PURPLE} ${COLOR_RESET}"
        case "$priority" in
            "critical")  printf "%s%s! %-55s%s%s %s[%s]%s\n" "$COLOR_RED" "$status" "$text" "$suffix" "$obs_icon" "$COLOR_DIM" "$id" "$COLOR_RESET" ;;
            "urgent")    printf "%s%s> %-55s%s%s %s[%s]%s\n" "$COLOR_YELLOW" "$status" "$text" "$suffix" "$obs_icon" "$COLOR_DIM" "$id" "$COLOR_RESET" ;;
            "important") printf "%s%s* %-55s%s%s %s[%s]%s\n" "$COLOR_BLUE" "$status" "$text" "$suffix" "$obs_icon" "$COLOR_DIM" "$id" "$COLOR_RESET" ;;
            *)           printf "%s  %-55s%s%s %s[%s]%s\n" "$status" "$text" "$suffix" "$obs_icon" "$COLOR_DIM" "$id" "$COLOR_RESET" ;;
        esac
    done

    # Finally print completed todos (if show_completed is enabled)
    if [[ "$SHOW_COMPLETED" == "true" ]]; then
        jq -r '.todos |
            map(select(.done == true)) |
            sort_by((if .priorities == "critical" then 0 elif .priorities == "urgent" then 1 elif .priorities == "important" then 2 else 3 end), .order_index) |
            .[] |
            (.text | split("\n")[0][0:55]) as $first_line |
            (.text | contains("\n")) as $multiline |
            (if .obsidian_ref then "true" else "false" end) as $obs |
            "\(.id)|✓|\(.priorities // "")|\($first_line)|\($multiline)|\($obs)"
        ' "$TODO_LIST_PATH" |
        while IFS='|' read -r id status priority text multiline obs; do
            suffix=""
            [[ "$multiline" == "true" ]] && suffix=" ..."
            obs_icon=""
            [[ "$obs" == "true" ]] && obs_icon="${COLOR_PURPLE} ${COLOR_RESET}"
            printf "%s%s  %-55s%s%s %s[%s]%s\n" "$COLOR_DIM" "$status" "$text" "$suffix" "$obs_icon" "$COLOR_DIM" "$id" "$COLOR_RESET"
        done
    fi
}

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
                            .done = false | .in_progress = false
                        elif .in_progress then
                            .in_progress = false | .done = true
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
        "revert")
            jq --arg id "$todo_id" '
                .todos |= map(
                    if .id == $id then
                        .in_progress = false |
                        .done = false
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
    SELECTION=$(format_todos | fzf --ansi --disabled --header="
 Todo Manager - ${ACTIVE_LIST_NAME}  (done: $done_count)
───────────────────────────────────────────────────
 ENTER: Cycle (pending>started>done)    x: Stop    X: Revert
 n: New    p: Paste new    e: Edit    P: Priority    K/J: Reorder
 d: Delete    D: Clear done    u: Undo    m: Move to list
 l: Switch list    L: List manager (new/rename/delete)
 v: View (select text)    y: Copy text    N: Description
 O: Send to Obsidian daily    /: Search
───────────────────────────────────────────────────
" \
        --prompt="" \
        --expect=enter,x,X,n,r,N,P,d,D,e,u,l,L,m,J,K,y,v,p,B,O,ctrl-up,ctrl-down,q,?,/ \
        --no-sort \
        --height=80% \
        --layout=reverse \
        --preview='preview_todo {} | fold -s -w $FZF_PREVIEW_COLUMNS' \
        --preview-window=right:40%)

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

    # Perform action based on key
    case "$KEY" in
        "enter"|"")
            if [[ -n "$TODO_ID" ]]; then
                update_todo "$TODO_ID" "toggle"
                echo "Toggled: $(jq -r --arg id "$TODO_ID" '.todos[] | select(.id == $id) | .text' "$TODO_LIST_PATH")"
                sleep 0.5
            fi
            ;;
        "x")
            if [[ -n "$TODO_ID" ]]; then
                update_todo "$TODO_ID" "stop"
                echo "Stopped: $(jq -r --arg id "$TODO_ID" '.todos[] | select(.id == $id) | .text' "$TODO_LIST_PATH")"
                sleep 0.5
            fi
            ;;
        "X")
            if [[ -n "$TODO_ID" ]]; then
                update_todo "$TODO_ID" "revert"
                echo "Reverted to pending: $(jq -r --arg id "$TODO_ID" '.todos[] | select(.id == $id) | .text' "$TODO_LIST_PATH")"
                sleep 0.5
            fi
            ;;
        "v")
            # view full text in less for text selection/copy
            if [[ -n "$TODO_ID" ]]; then
                VIEW_TMP=$(mktemp /tmp/todo_view.XXXXXX)
                TODO_OBJ=$(jq -r --arg id "$TODO_ID" '.todos[] | select(.id == $id)' "$TODO_LIST_PATH")
                VIEW_TEXT=$(echo "$TODO_OBJ" | jq -r '.text // ""')
                VIEW_DESC=$(echo "$TODO_OBJ" | jq -r '.description // ""')
                VIEW_PRIORITY=$(echo "$TODO_OBJ" | jq -r '.priorities // "default"')
                VIEW_STATUS="pending"
                echo "$TODO_OBJ" | jq -e '.in_progress == true' &>/dev/null && VIEW_STATUS="in-progress"
                echo "$TODO_OBJ" | jq -e '.done == true' &>/dev/null && VIEW_STATUS="done"

                {
                    echo "[$VIEW_STATUS] [$VIEW_PRIORITY]"
                    echo "────────────────────────────────────────"
                    echo ""
                    echo "$VIEW_TEXT"
                    if [[ -n "$VIEW_DESC" ]]; then
                        echo ""
                        echo "── description ─────────────────────────"
                        echo "$VIEW_DESC"
                    fi
                    echo ""
                    echo "────────────────────────────────────────"
                    echo "select text with mouse/keyboard, q to exit"
                } > "$VIEW_TMP"

                less -R "$VIEW_TMP"
                rm -f "$VIEW_TMP"
            fi
            ;;
        "N")
            # add/edit description on a todo
            if [[ -n "$TODO_ID" ]]; then
                CURRENT_DESC=$(jq -r --arg id "$TODO_ID" '.todos[] | select(.id == $id) | .description // ""' "$TODO_LIST_PATH")
                if [[ "$LONG_DESC" == true ]]; then
                    DESC_TMP=$(mktemp /tmp/todo_desc.XXXXXX)
                    [[ -n "$CURRENT_DESC" ]] && printf '%s' "$CURRENT_DESC" > "$DESC_TMP"
                    nvim -u NONE -c "edit $DESC_TMP" -c 'set noswapfile nobackup nowritebackup wrap linebreak' -c 'nnoremap <buffer> q :wq<CR>'
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
        "K"|"ctrl-up")
            if [[ -n "$TODO_ID" ]]; then
                update_todo "$TODO_ID" "move_up"
                # no sleep - immediately refresh to show new position
            fi
            ;;
        "J"|"ctrl-down")
            if [[ -n "$TODO_ID" ]]; then
                update_todo "$TODO_ID" "move_down"
                # no sleep - immediately refresh to show new position
            fi
            ;;
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
                    jq --arg id "$TODO_ID" '
                        (.todos[] | select(.id == $id)) as $deleted |
                        .todos |= map(select(.id != $id)) |
                        ._metadata.deleted_todos = ([$deleted] + (._metadata.deleted_todos // []))[0:10] |
                        ._metadata.updated_at = (now | floor)
                    ' "$TODO_LIST_PATH" > "${TODO_LIST_PATH}.tmp" && mv "${TODO_LIST_PATH}.tmp" "$TODO_LIST_PATH"
                    echo "Deleted (press 'u' to undo)"
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
            # Undo last delete
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
                sleep 0.5
            else
                echo "Nothing to undo"
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
                --preview-window=right:40%)

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
            # Show help
            clear
            echo ""
            echo " Todo Manager - Help"
            echo " ─────────────────────────────────────────"
            echo ""
            echo " Navigation"
            echo "   j/k or arrows    Move up/down in list"
            echo "   K/J              Reorder todo (move up/down)"
            echo ""
            echo " Status Changes"
            echo "   Enter            Cycle (pending > started > done)"
            echo "   x                Stop in-progress"
            echo "   X                Revert to pending"
            echo ""
            echo " Editing"
            echo "   n                New todo"
            echo "   p                Paste new todo from clipboard"
            echo "   e                Edit todo text"
            echo "   P                Set priority"
            echo "   (In edit mode: Enter = save, Esc = cancel)"
            echo ""
            echo " Delete/Undo"
            echo "   d                Delete todo (can undo)"
            echo "   D                Delete all completed"
            echo "   u                Undo last delete"
            echo ""
            echo " View/Copy"
            echo "   v                View full text (scrollable, q to exit)"
            echo "   N                Edit note in \$EDITOR"
            echo "   y                Copy text to clipboard"
            echo ""
            echo " Obsidian"
            echo "   O                Send to today's daily note"
            echo ""
            echo " Search"
            echo "   /                Search/filter todos"
            echo ""
            echo " Lists"
            echo "   l                Switch lists"
            echo "   L                List manager (create/rename/delete)"
            echo "   m                Move todo to another list"
            echo ""
            echo " ─────────────────────────────────────────"
            echo " Press any key to return..."
            read -n 1 -s
            ;;
    esac
done

echo "Exiting todo manager"