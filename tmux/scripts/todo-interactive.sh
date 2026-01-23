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
        jq -r --arg id "$todo_id" '
            .todos[] | select(.id == $id) |
            "Priority: \(.priorities // "none")\n" +
            "Status: \(if .in_progress then "In Progress" elif .done then "Done" else "Pending" end)\n" +
            "────────────────────────────────────────\n" +
            .text
        ' "$TODO_LIST_PATH" 2>/dev/null || echo "No preview available"
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
    # Show todos and prompt for selection
    SELECTION=$(format_todos | fzf --ansi --disabled --header="
╭────────────────────────────────────────────────────────╮
│ Todo Manager - Daily List                              │
├────────────────────────────────────────────────────────┤
│ ENTER: Toggle done       s: Start/In-progress          │
│ c: Create new todo       x: Stop in-progress           │
│ X: Revert to pending     p: Set priority               │
│ K/C-Up: Move up          J/C-Down: Move down           │
│ d: Delete    v: View full    r: Refresh    q: Quit     │
╰────────────────────────────────────────────────────────╯
" \
        --prompt="" \
        --expect=enter,s,x,X,c,r,p,d,v,J,K,ctrl-up,ctrl-down,q \
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
    TODO_ID=$(echo "$TODO_LINE" | grep -oE '\[[^]]+\]$' | tr -d '[]')

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
        "d")
            if [[ -n "$TODO_ID" ]]; then
                TODO_TEXT=$(jq -r --arg id "$TODO_ID" '.todos[] | select(.id == $id) | .text' "$TODO_LIST_PATH")
                echo -n "Delete '$TODO_TEXT'? (y/N): "
                read -n 1 -r CONFIRM
                echo
                if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
                    update_todo "$TODO_ID" "delete"
                    echo "Deleted."
                    sleep 0.5
                fi
            fi
            ;;
        "v")
            # View full todo details
            if [[ -n "$TODO_ID" ]]; then
                clear
                echo ""
                echo "═══════════════════════════════════════════════"
                echo "                 Todo Details"
                echo "═══════════════════════════════════════════════"
                echo ""
                jq -r --arg id "$TODO_ID" '
                    .todos[] | select(.id == $id) |
                    "Priority: \(.priorities // "none")\n" +
                    "Status: \(if .in_progress then "In Progress" elif .done then "Done" else "Pending" end)\n" +
                    "Created: \(.timestamp | todate)\n" +
                    "─────────────────────────────────────────────\n" +
                    .text
                ' "$TODO_LIST_PATH"
                echo ""
                echo "─────────────────────────────────────────────"
                echo "Press any key to return..."
                read -n 1 -s
            fi
            ;;
        "c")
            # Create new todo with multi-line support
            echo ""
            echo "═══════════════════════════════════════════════"
            echo "Create New Todo (press Enter twice when done)"
            echo "Multi-line supported - newlines are preserved"
            echo "═══════════════════════════════════════════════"
            echo ""

            # Collect multi-line input preserving newlines
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
                    # Preserve empty line as newline
                    if [[ -n "$TODO_LINES" ]]; then
                        TODO_LINES="${TODO_LINES}"$'\n'
                    fi
                else
                    EMPTY_COUNT=0
                    if [[ -z "$TODO_LINES" ]]; then
                        TODO_LINES="$line"
                    else
                        TODO_LINES="${TODO_LINES}"$'\n'"${line}"
                    fi
                fi
            done

            # Remove trailing blank line from double-enter detection
            TODO_TEXT="${TODO_LINES%$'\n'}"

            if [[ -n "$TODO_TEXT" ]]; then
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