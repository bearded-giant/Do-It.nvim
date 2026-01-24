#!/bin/bash

# Status bar segment for displaying current todo
# Outputs: icon + truncated todo text
# Use in tmux status bar: #(path/to/todo-status.sh)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/get-active-list.sh"

TODO_LIST_PATH="$(get_active_list_path)"
CHAR_LIMIT="${DOIT_CHAR_LIMIT:-25}"

# Icons (nerd font)
ICON_TASK=""
ICON_CHECK=""

if ! command -v jq &> /dev/null; then
    echo ""
    exit 0
fi

if [[ ! -f "$TODO_LIST_PATH" ]]; then
    echo ""
    exit 0
fi

# get in-progress todo first
todo_text=$(jq -r '.todos[] | select(.in_progress == true) | .text' "$TODO_LIST_PATH" 2>/dev/null | head -1)

# fallback to first pending todo
if [[ -z "$todo_text" ]]; then
    todo_text=$(jq -r '.todos | sort_by(.order_index) | .[] | select(.done == false) | .text' "$TODO_LIST_PATH" 2>/dev/null | head -1)

    if [[ -z "$todo_text" ]]; then
        echo "$ICON_CHECK All done!"
        exit 0
    fi
fi

# trim whitespace
todo_text="${todo_text#"${todo_text%%[![:space:]]*}"}"
todo_text="${todo_text%"${todo_text##*[![:space:]]}"}"

# truncate
if [[ ${#todo_text} -gt $CHAR_LIMIT ]]; then
    todo_text="${todo_text:0:$CHAR_LIMIT}..."
fi

printf '%s %s\n' "$ICON_TASK" "$todo_text"
