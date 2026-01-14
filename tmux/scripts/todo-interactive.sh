#!/bin/bash

# Interactive todo manager for tmux using fzf
TODO_LIST_PATH="$HOME/.local/share/nvim/doit/lists/daily.json"

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

# Check if the daily list file exists
if [[ ! -f "$TODO_LIST_PATH" ]]; then
    echo "Error: Daily todo list not found at $TODO_LIST_PATH"
    exit 1
fi

# Priority color codes
priority_color() {
    case "$1" in
        "critical") echo "\033[1;31m" ;;  # bold red
        "urgent")   echo "\033[1;33m" ;;  # bold yellow
        "important") echo "\033[1;34m" ;; # bold blue
        *)          echo "" ;;
    esac
}

# Priority indicator
priority_indicator() {
    case "$1" in
        "critical") echo "!" ;;
        "urgent")   echo ">" ;;
        "important") echo "*" ;;
        *)          echo " " ;;
    esac
}

# Function to display todos in a formatted way (excludes done todos)
format_todos() {
    # First print in-progress todos
    jq -r '.todos |
        map(select(.in_progress == true)) |
        sort_by(.order_index) |
        .[] |
        "\(.id)|\(if .in_progress then "▶" elif .done then "✓" else " " end)|\(.priorities // "")|\(.text[0:70])"
    ' "$TODO_LIST_PATH" |
    while IFS='|' read -r id status priority text; do
        local pcolor=$(priority_color "$priority")
        local pind=$(priority_indicator "$priority")
        if [[ -n "$pcolor" ]]; then
            printf "\033[1;32m%s${pcolor}%s %-70s\033[0m\n" "$status" "$pind" "$text"
        else
            printf "\033[1;32m%s%s %-70s\033[0m\n" "$status" "$pind" "$text"
        fi
    done

    # Then print not started todos
    jq -r '.todos |
        map(select(.done == false and .in_progress != true)) |
        sort_by(.order_index) |
        .[] |
        "\(.id)|\(if .in_progress then "▶" elif .done then "✓" else " " end)|\(.priorities // "")|\(.text[0:70])"
    ' "$TODO_LIST_PATH" |
    while IFS='|' read -r id status priority text; do
        local pcolor=$(priority_color "$priority")
        local pind=$(priority_indicator "$priority")
        if [[ -n "$pcolor" ]]; then
            printf "%s${pcolor}%s %-70s\033[0m\n" "$status" "$pind" "$text"
        else
            printf "%s%s %-70s\n" "$status" "$pind" "$text"
        fi
    done
}

# Priority options (matches Neovim config)
PRIORITIES=("critical" "urgent" "important" "none")

# Function to select priority via fzf
select_priority() {
    local current_priority="${1:-none}"
    local header="$2"

    printf '%s\n' "${PRIORITIES[@]}" | fzf --ansi \
        --header="${header:-Select Priority}" \
        --prompt="Priority > " \
        --height=10 \
        --layout=reverse \
        --no-sort \
        --query="$current_priority" \
        --select-1
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
            if [[ "$new_priority" == "none" ]]; then
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
    esac
}

# Main interactive loop
while true; do
    # Show todos and prompt for selection
    SELECTION=$(format_todos | fzf --ansi --header="
╭───────────────────────────────────────────────────╮
│ Todo Manager - Daily List                         │
├───────────────────────────────────────────────────┤
│ ENTER: Toggle done       s: Start/In-progress     │
│ c: Create new todo       x: Stop in-progress      │
│ X: Revert to pending     p: Set priority          │
│ K/C-Up: Move up          J/C-Down: Move down      │
│ r: Refresh               q/ESC: Quit              │
╰───────────────────────────────────────────────────╯
" \
        --prompt="Select todo > " \
        --expect=enter,s,x,X,c,r,p,J,K,ctrl-up,ctrl-down,q \
        --no-sort \
        --height=35 \
        --layout=reverse)

    # Parse the selection
    KEY=$(echo "$SELECTION" | head -1)
    TODO_LINE=$(echo "$SELECTION" | tail -1)

    # Exit on q or escape
    if [[ "$KEY" == "q" ]] || [[ -z "$TODO_LINE" ]]; then
        break
    fi

    # Extract the todo text from the selected line (remove leading status, priority indicator, and spaces)
    TODO_TEXT=$(echo "$TODO_LINE" | sed 's/^[▶✓ !>*]*//g' | sed 's/^ *//g' | xargs)

    # Find the todo ID by matching the text (compare first part of text to handle truncation)
    if [[ -n "$TODO_TEXT" ]]; then
        TODO_ID=$(jq -r --arg text "$TODO_TEXT" '.todos[] | select(.text | startswith($text)) | .id' "$TODO_LIST_PATH" | head -1)
    else
        TODO_ID=""
    fi

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
                CURRENT_PRIORITY=$(jq -r --arg id "$TODO_ID" '.todos[] | select(.id == $id) | .priorities // "none"' "$TODO_LIST_PATH")
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
        "c")
            # Create new todo
            echo ""
            echo "═══════════════════════════════════════════════"
            echo "Create New Todo (press Enter twice when done)"
            echo "═══════════════════════════════════════════════"
            echo ""

            # Collect multi-line input
            TODO_LINES=""
            EMPTY_COUNT=0

            while true; do
                read -r line

                # Check for double enter (two empty lines to finish)
                if [[ -z "$line" ]]; then
                    EMPTY_COUNT=$((EMPTY_COUNT + 1))
                    if [[ $EMPTY_COUNT -ge 2 ]]; then
                        break
                    fi
                    # Add single newline to preserve formatting
                    TODO_LINES="${TODO_LINES} "
                else
                    EMPTY_COUNT=0
                    if [[ -z "$TODO_LINES" ]]; then
                        TODO_LINES="$line"
                    else
                        TODO_LINES="${TODO_LINES} ${line}"
                    fi
                fi
            done

            # Trim and check if we have text
            TODO_TEXT=$(echo "$TODO_LINES" | xargs)

            if [[ -n "$TODO_TEXT" ]]; then
                # Select priority
                echo ""
                SELECTED_PRIORITY=$(select_priority "none" "Select Priority (ESC for none)")

                # Generate unique ID
                TODO_ID="$(date +%s)_$(( RANDOM * RANDOM % 9999999 ))"

                # Get the highest order_index
                MAX_ORDER=$(jq '.todos | map(.order_index) | max // 0' "$TODO_LIST_PATH")
                NEW_ORDER=$((MAX_ORDER + 1))

                # Add the new todo (with or without priority)
                if [[ -n "$SELECTED_PRIORITY" && "$SELECTED_PRIORITY" != "none" ]]; then
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
                          timestamp: (now | floor),
                          priorities: $priority,
                          "_score": 10
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
                          timestamp: (now | floor),
                          "_score": 10
                       }] |
                       ._metadata.updated_at = (now | floor)' \
                       "$TODO_LIST_PATH" > "${TODO_LIST_PATH}.tmp" && mv "${TODO_LIST_PATH}.tmp" "$TODO_LIST_PATH"
                fi

                if [[ $? -eq 0 ]]; then
                    echo ""
                    if [[ -n "$SELECTED_PRIORITY" && "$SELECTED_PRIORITY" != "none" ]]; then
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
                echo "No text entered, cancelled"
                sleep 1
            fi
            ;;
        "r")
            echo "Refreshed"
            sleep 0.3
            ;;
    esac
done

echo "Exiting todo manager"