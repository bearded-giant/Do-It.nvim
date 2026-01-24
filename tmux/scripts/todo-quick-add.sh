#!/bin/bash

# Quick add todo with inline multi-line support

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/get-active-list.sh"

TODO_LIST_PATH="$(get_active_list_path)"

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    tmux display-message "Error: jq is required but not installed"
    exit 1
fi

# Check if the list file exists
if [[ ! -f "$TODO_LIST_PATH" ]]; then
    tmux display-message "Error: Todo list not found"
    exit 1
fi

# Create a temporary file
TEMP_FILE=$(mktemp /tmp/todo_quick.XXXXXX)

# Use tmux command prompt for input
tmux command-prompt -p "New todo:" "run-shell 'echo \"%%\" | $0 --process'"

# If called with --process, handle the actual todo creation
if [[ "$1" == "--process" ]]; then
    # Read from stdin
    TODO_TEXT=$(cat)

    if [[ -z "$TODO_TEXT" ]]; then
        tmux display-message "No todo text entered"
        exit 0
    fi

    # Create backup
    cp "$TODO_LIST_PATH" "${TODO_LIST_PATH}.bak"

    # Generate a unique ID
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
          created_at: (now | floor)
       }] |
       ._metadata.updated_at = (now | floor)' \
       "$TODO_LIST_PATH" > "${TODO_LIST_PATH}.tmp" && mv "${TODO_LIST_PATH}.tmp" "$TODO_LIST_PATH"

    if [[ $? -eq 0 ]]; then
        tmux display-message "✓ Todo added: $TODO_TEXT"
    else
        tmux display-message "Error: Failed to add todo"
        mv "${TODO_LIST_PATH}.bak" "$TODO_LIST_PATH"
    fi
fi