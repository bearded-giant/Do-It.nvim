#!/bin/bash

# Mark the next undone todo as in-progress

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/get-active-list.sh"

TODO_LIST_PATH="$(get_active_list_path)"

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed"
    exit 1
fi

# Check if the list file exists
if [[ ! -f "$TODO_LIST_PATH" ]]; then
    tmux display-message "Error: Todo list not found"
    exit 1
fi

# Create a backup
cp "$TODO_LIST_PATH" "${TODO_LIST_PATH}.bak"

# Clear any existing in_progress flags and mark the next undone todo as in_progress
NEXT_TODO=$(jq -r '
    .todos |
    sort_by(.order_index) |
    map(select(.done == false)) |
    first |
    .id // empty
' "$TODO_LIST_PATH")

if [[ -z "$NEXT_TODO" ]]; then
    tmux display-message "No pending todos to start"
    exit 0
fi

# Update the todo list
jq --arg next_id "$NEXT_TODO" '
    .todos |= map(
        if .id == $next_id then
            .in_progress = true
        else
            .in_progress = false
        end
    ) |
    ._metadata.updated_at = (now | floor)
' "$TODO_LIST_PATH" > "${TODO_LIST_PATH}.tmp" && mv "${TODO_LIST_PATH}.tmp" "$TODO_LIST_PATH"

# Get the text of the newly in-progress todo
TODO_TEXT=$(jq -r --arg id "$NEXT_TODO" '.todos[] | select(.id == $id) | .text' "$TODO_LIST_PATH")
tmux display-message "▶ Started: $TODO_TEXT"