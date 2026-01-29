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
COLOR_DIM=$'\e[2m'

# preview command for fzf - shows full todo content with line wrapping
preview_todo() {
    local line="$1"
    local todo_id=$(echo "$line" | grep -oE '\[[^]]+\]$' | tr -d '[]')
    if [[ -n "$todo_id" ]]; then
        # use printf to safely output text with special chars (backticks, etc)
        local priority=$(jq -r --arg id "$todo_id" '.todos[] | select(.id == $id) | .priorities // "none"' "$TODO_LIST_PATH" 2>/dev/null)
        local status=$(jq -r --arg id "$todo_id" '.todos[] | select(.id == $id) | if .in_progress then "In Progress" elif .done then "Done" else "Pending" end' "$TODO_LIST_PATH" 2>/dev/null)
        local text=$(jq -r --arg id "$todo_id" '.todos[] | select(.id == $id) | .text' "$TODO_LIST_PATH" 2>/dev/null)

        printf 'ID: %s\n' "$todo_id"
        printf 'Priority: %s\n' "$priority"
        printf 'Status: %s\n' "$status"
        echo "────────────────────────────────────────"
        printf '%s\n' "$text"
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
        sort_by(.order_index) |
        .[] |
        (.text | split("\n")[0][0:55]) as $first_line |
        (.text | contains("\n")) as $multiline |
        "\(.id)|\(if .in_progress then "▶" elif .done then "✓" else " " end)|\(.priorities // "")|\($first_line)|\($multiline)"
    ' "$TODO_LIST_PATH" |
    while IFS='|' read -r id status priority text multiline; do
        # Add ... for multi-line items
        suffix=""
        [[ "$multiline" == "true" ]] && suffix=" ..."
        # Append ID at end (dimmed) for reliable extraction
        case "$priority" in
            "critical")  printf "%s%s%s! %-55s%s %s[%s]%s\n" "$COLOR_GREEN" "$status" "$COLOR_RED" "$text" "$suffix" "$COLOR_DIM" "$id" "$COLOR_RESET" ;;
            "urgent")    printf "%s%s%s> %-55s%s %s[%s]%s\n" "$COLOR_GREEN" "$status" "$COLOR_YELLOW" "$text" "$suffix" "$COLOR_DIM" "$id" "$COLOR_RESET" ;;
            "important") printf "%s%s%s* %-55s%s %s[%s]%s\n" "$COLOR_GREEN" "$status" "$COLOR_BLUE" "$text" "$suffix" "$COLOR_DIM" "$id" "$COLOR_RESET" ;;
            *)           printf "%s%s  %-55s%s %s[%s]%s\n" "$COLOR_GREEN" "$status" "$text" "$suffix" "$COLOR_DIM" "$id" "$COLOR_RESET" ;;
        esac
    done

    # Then print not started todos
    jq -r '.todos |
        map(select(.done == false and .in_progress != true)) |
        sort_by(.order_index) |
        .[] |
        (.text | split("\n")[0][0:55]) as $first_line |
        (.text | contains("\n")) as $multiline |
        "\(.id)|\(if .in_progress then "▶" elif .done then "✓" else " " end)|\(.priorities // "")|\($first_line)|\($multiline)"
    ' "$TODO_LIST_PATH" |
    while IFS='|' read -r id status priority text multiline; do
        suffix=""
        [[ "$multiline" == "true" ]] && suffix=" ..."
        case "$priority" in
            "critical")  printf "%s%s! %-55s%s %s[%s]%s\n" "$COLOR_RED" "$status" "$text" "$suffix" "$COLOR_DIM" "$id" "$COLOR_RESET" ;;
            "urgent")    printf "%s%s> %-55s%s %s[%s]%s\n" "$COLOR_YELLOW" "$status" "$text" "$suffix" "$COLOR_DIM" "$id" "$COLOR_RESET" ;;
            "important") printf "%s%s* %-55s%s %s[%s]%s\n" "$COLOR_BLUE" "$status" "$text" "$suffix" "$COLOR_DIM" "$id" "$COLOR_RESET" ;;
            *)           printf "%s  %-55s%s %s[%s]%s\n" "$status" "$text" "$suffix" "$COLOR_DIM" "$id" "$COLOR_RESET" ;;
        esac
    done
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
[[ "$USE_EDITOR" == "true" ]] && USE_EDITOR=true || USE_EDITOR=false

# Edit/create text input
# Usage: result=$(input_text "prefill"); status=$?
# Returns: text on success, exit 130 on cancel (Esc)
input_text() {
    local prefill="$1"
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
        result=$(echo "" | fzf --print-query --query="$prefill" \
            --height=3 \
            --layout=reverse \
            --no-info \
            --bind 'enter:accept' \
            --bind 'esc:abort' | head -1)
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
                .todos |= map(
                    if .id == $id then
                        .done = (if .done then false else true end) |
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
    SELECTION=$(format_todos | fzf --ansi --disabled --header="
 Todo Manager - ${ACTIVE_LIST_NAME}
───────────────────────────────────────────────────
 ENTER: Toggle    s: Start    x: Stop    X: Revert
 n: New    e: Edit    p: Priority    K/J: Reorder
 d: Delete    D: Clear done    u: Undo    m: Move to list
 l: Switch list    L: List manager (new/rename/delete)
 SPACE: View note    y: Copy text
───────────────────────────────────────────────────
" \
        --prompt="" \
        --expect=enter,space,s,x,X,n,r,p,d,D,e,u,l,L,m,J,K,y,ctrl-up,ctrl-down,q,? \
        --no-sort \
        --height=80% \
        --layout=reverse \
        --preview='bash -c "preview_todo {}"' \
        --preview-window=right:40%:wrap)

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
        "s")
            if [[ -n "$TODO_ID" ]]; then
                update_todo "$TODO_ID" "start"
                echo "Started: $(jq -r --arg id "$TODO_ID" '.todos[] | select(.id == $id) | .text' "$TODO_LIST_PATH")"
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
        "p")
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
                        echo "$TODO_OBJ" | jq -s '.[0]' | jq -s --slurpfile todo /dev/stdin '
                            .[0].todos += $todo |
                            .[0]._metadata.updated_at = (now | floor)
                        ' "$TARGET_PATH" > "${TARGET_PATH}.tmp" && mv "${TARGET_PATH}.tmp" "$TARGET_PATH"

                        TODO_TEXT=$(echo "$TODO_OBJ" | jq -r '.text | split("\n")[0][0:30]')
                        echo "Moved to $TARGET_LIST: $TODO_TEXT"
                        sleep 0.5
                    fi
                fi
            fi
            ;;
        "space")
            # view full note text in pager (supports tmux copy mode)
            if [[ -n "$TODO_ID" ]]; then
                {
                    jq -r --arg id "$TODO_ID" '
                        .todos[] | select(.id == $id) |
                        "Priority: \(.priorities // "none")" + "\n" +
                        "Status: \(if .in_progress then "In Progress" elif .done then "Done" else "Pending" end)" + "\n" +
                        "Created: \(.timestamp | todate)" + "\n" +
                        "\n─────────────────────────────────────────────\n\n" +
                        .text
                    ' "$TODO_LIST_PATH" 2>/dev/null
                } | less -R
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
                          priorities: $priority                       }] |
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
                          created_at: (now | floor)                       }] |
                       ._metadata.updated_at = (now | floor)' \
                       "$TODO_LIST_PATH" > "${TODO_LIST_PATH}.tmp" && mv "${TODO_LIST_PATH}.tmp" "$TODO_LIST_PATH"
                fi

                if [[ $? -eq 0 ]]; then
                    echo ""
                    if [[ -n "$SELECTED_PRIORITY" && "$SELECTED_PRIORITY" != "default" ]]; then
                        echo "✓ Created [$SELECTED_PRIORITY]: $TODO_TEXT"
                    else
                        echo "✓ Created: $TODO_TEXT"
                    fi

                    # Ask if should mark as in-progress
                    echo ""
                    echo -n "Mark as in-progress? (y/N): "
                    read -n 1 -r MARK_PROGRESS
                    echo

                    if [[ "$MARK_PROGRESS" =~ ^[Yy]$ ]]; then
                        # Clear other in_progress and set this one
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
                        echo "▶ Marked as in-progress"
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
            echo "   Enter            Toggle done/pending"
            echo "   s                Start (mark in-progress)"
            echo "   x                Stop in-progress"
            echo "   X                Revert to pending"
            echo ""
            echo " Editing"
            echo "   n                New todo"
            echo "   e                Edit todo text"
            echo "   p                Set priority"
            echo "   (In new/edit: Enter = save, Esc = cancel)"
            echo ""
            echo " Delete/Undo"
            echo "   d                Delete todo (can undo)"
            echo "   D                Delete all completed"
            echo "   u                Undo last delete"
            echo ""
            echo " View/Copy"
            echo "   Space            View full note (scrollable, q to exit)"
            echo "   y                Copy text to clipboard"
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