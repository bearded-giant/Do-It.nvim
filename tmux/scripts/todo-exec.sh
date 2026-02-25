#!/bin/bash

# Get the current in-progress todo from active list

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/get-active-list.sh"

TODO_LIST_PATH="$(get_active_list_path)"
CHAR_LIMIT=25
ICON_TASK=$'\xef\x82\xae'
ICON_CHECK=$'\xef\x80\x8c'

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo ""
    exit 0
fi

# Check if the list file exists
if [[ ! -f "$TODO_LIST_PATH" ]]; then
    echo ""
    exit 0
fi

# get in-progress todo first (grab priority alongside)
todo_json=$(jq -r '[.todos[] | select(.in_progress == true)][0] // empty | "\(.priorities // "")\t\(.text)"' "$TODO_LIST_PATH" 2>/dev/null)
todo_status="active"

if [[ -z "$todo_json" ]]; then
    # fallback to first pending todo
    todo_json=$(jq -r '[.todos | sort_by(.order_index) | .[] | select(.done == false)][0] // empty | "\(.priorities // "")\t\(.text)"' "$TODO_LIST_PATH" 2>/dev/null)
    todo_status="pending"

    if [[ -z "$todo_json" ]]; then
        COLOR=$(tmux show -gqv @doit-color-done 2>/dev/null)
        [[ -n "$COLOR" ]] && tmux set -gq @doit-todo-fg "$COLOR"
        echo "$ICON_CHECK All done!"
        exit 0
    fi
fi

todo_priority=$(printf '%s' "$todo_json" | cut -f1)
todo_text=$(printf '%s' "$todo_json" | cut -f2-)

# pick color: priority overrides status
case "$todo_priority" in
    critical)  COLOR=$(tmux show -gqv @doit-color-critical 2>/dev/null) ;;
    urgent)    COLOR=$(tmux show -gqv @doit-color-urgent 2>/dev/null) ;;
    important) COLOR=$(tmux show -gqv @doit-color-important 2>/dev/null) ;;
    *)
        if [[ "$todo_status" == "active" ]]; then
            COLOR=$(tmux show -gqv @doit-color-active 2>/dev/null)
        else
            COLOR=$(tmux show -gqv @doit-color-pending 2>/dev/null)
        fi
        ;;
esac
[[ -n "$COLOR" ]] && tmux set -gq @doit-todo-fg "$COLOR"

# trim whitespace
todo_text="${todo_text#"${todo_text%%[![:space:]]*}"}"
todo_text="${todo_text%"${todo_text##*[![:space:]]}"}"

if [[ ${#todo_text} -gt $CHAR_LIMIT ]]; then
    todo_text="${todo_text:0:$CHAR_LIMIT}..."
fi

printf '%s\n' "$todo_text"
