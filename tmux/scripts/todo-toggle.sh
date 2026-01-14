#!/bin/bash

# Toggle the completion status of the current in-progress todo
TODO_LIST_PATH="$HOME/.local/share/nvim/doit/lists/daily.json"

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed"
    exit 1
fi

# Check if the daily list file exists
if [[ ! -f "$TODO_LIST_PATH" ]]; then
    echo "Error: Daily todo list not found at $TODO_LIST_PATH"
    exit 1
fi

# Create a backup
cp "$TODO_LIST_PATH" "${TODO_LIST_PATH}.bak"

# Get the ID of the current in-progress todo
TODO_ID=$(jq -r '.todos[] | select(.in_progress == true) | .id' "$TODO_LIST_PATH" 2>/dev/null | head -1)

if [[ -z "$TODO_ID" ]]; then
    # No in-progress todo, get the first undone todo
    TODO_ID=$(jq -r '.todos | sort_by(.order_index) | .[] | select(.done == false) | .id' "$TODO_LIST_PATH" 2>/dev/null | head -1)

    if [[ -z "$TODO_ID" ]]; then
        tmux display-message "No active todos to toggle"
        exit 0
    fi
fi

# Toggle the done status and clear in_progress flag
jq --arg id "$TODO_ID" '
    .todos |= map(
        if .id == $id then
            .done = (if .done then false else true end) |
            .in_progress = false
        else . end
    ) |
    ._metadata.updated_at = (now | floor)
' "$TODO_LIST_PATH" > "${TODO_LIST_PATH}.tmp" && mv "${TODO_LIST_PATH}.tmp" "$TODO_LIST_PATH"

# Get the text of the toggled todo for feedback
TODO_TEXT=$(jq -r --arg id "$TODO_ID" '.todos[] | select(.id == $id) | .text' "$TODO_LIST_PATH")
TODO_STATUS=$(jq -r --arg id "$TODO_ID" '.todos[] | select(.id == $id) | .done' "$TODO_LIST_PATH")

if [[ "$TODO_STATUS" == "true" ]]; then
    tmux display-message "✓ Completed: $TODO_TEXT"
else
    tmux display-message "↻ Reopened: $TODO_TEXT"
fi