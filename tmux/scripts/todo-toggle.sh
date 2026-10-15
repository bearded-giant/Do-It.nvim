#!/bin/bash

# Toggle the completion status of the current in-progress todo

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/get-active-list.sh"
source "$SCRIPT_DIR/lib-twin.sh"

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
            .in_progress = false |
            if .done then .completed_at = (now | floor) else del(.completed_at) end
        else . end
    ) |
    ._metadata.updated_at = (now | floor)
' "$TODO_LIST_PATH" > "${TODO_LIST_PATH}.tmp" && mv "${TODO_LIST_PATH}.tmp" "$TODO_LIST_PATH"

# Get the text of the toggled todo for feedback
TODO_TEXT=$(jq -r --arg id "$TODO_ID" '.todos[] | select(.id == $id) | .text' "$TODO_LIST_PATH")
read -r TODO_STATUS COMPLETED_AT < <(jq -r --arg id "$TODO_ID" \
    '.todos[] | select(.id == $id) | "\(.done) \(.completed_at // "")"' "$TODO_LIST_PATH")
TWIN_REF=$(twin_ref "$TODO_LIST_PATH" "$TODO_ID")

if [[ "$TODO_STATUS" == "true" ]]; then
    TWIN_MSG=$(twin_apply "$TWIN_REF" complete "$COMPLETED_AT")
    tmux display-message "✓ Completed: $TODO_TEXT${TWIN_MSG:+ · $TWIN_MSG}"
else
    TWIN_MSG=$(twin_apply "$TWIN_REF" revert)
    tmux display-message "↻ Reopened: $TODO_TEXT${TWIN_MSG:+ · $TWIN_MSG}"
fi