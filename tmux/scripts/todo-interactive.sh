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

# Function to display todos in a formatted way (excludes done todos)
format_todos() {
    # First print in-progress todos
    jq -r '.todos |
        map(select(.in_progress == true)) |
        sort_by(.order_index) |
        .[] |
        "\(.id)|\(if .in_progress then "▶" elif .done then "✓" else " " end)|\(.text[0:80])"
    ' "$TODO_LIST_PATH" |
    while IFS='|' read -r id status text; do
        printf "\033[1;32m%s %-80s\033[0m\n" "$status" "$text"
    done

    # Then print not started todos
    jq -r '.todos |
        map(select(.done == false and .in_progress != true)) |
        sort_by(.order_index) |
        .[] |
        "\(.id)|\(if .in_progress then "▶" elif .done then "✓" else " " end)|\(.text[0:80])"
    ' "$TODO_LIST_PATH" |
    while IFS='|' read -r id status text; do
        printf "%s %-80s\n" "$status" "$text"
    done
}

# Function to update todo status
update_todo() {
    local todo_id="$1"
    local action="$2"

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
│ X: Revert to pending     r: Refresh               │
│ q/ESC: Quit                                       │
╰───────────────────────────────────────────────────╯
" \
        --prompt="Select todo > " \
        --expect=enter,s,x,X,c,r,q \
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

    # Extract the todo text from the selected line (remove leading status and spaces)
    TODO_TEXT=$(echo "$TODO_LINE" | sed 's/^[▶✓ ]*//g' | sed 's/^ *//g' | xargs)

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
                # Generate unique ID
                TODO_ID="$(date +%s)_$(( RANDOM * RANDOM % 9999999 ))"

                # Get the highest order_index
                MAX_ORDER=$(jq '.todos | map(.order_index) | max // 0' "$TODO_LIST_PATH")
                NEW_ORDER=$((MAX_ORDER + 1))

                # Add the new todo
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

                if [[ $? -eq 0 ]]; then
                    echo ""
                    echo "✓ Created: $TODO_TEXT"

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