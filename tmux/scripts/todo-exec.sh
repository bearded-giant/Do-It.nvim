#!/bin/bash

# Get the current in-progress todo from the window's list, labelled
# "<session>:<window>"; outside tmux the list name is the label.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/get-active-list.sh"

# status line passes #{window_id} as $1 — #() has no client context; by hand,
# '<session>:<window>' names a window too
[[ -n "$1" ]] && export DOIT_WINDOW="$1"

ACTIVE_LIST_NAME="$(get_active_list_name)"
TODO_LIST_PATH="$LISTS_DIR/${ACTIVE_LIST_NAME}.json"
CHAR_LIMIT=$(tmux show -gqv @doit-todo-chars 2>/dev/null)
CHAR_LIMIT=${CHAR_LIMIT:-25}
LIST_CHAR_LIMIT=$(tmux show -gqv @doit-list-chars 2>/dev/null)
# outside tmux there is no window, so the list name stands in as the label
WINDOW_KEY=$(get_tmux_window_key 2>/dev/null) || WINDOW_KEY=""
LIST_LABEL="${WINDOW_KEY:-$ACTIVE_LIST_NAME}"
[[ -n "$LIST_CHAR_LIMIT" && ${#LIST_LABEL} -gt $LIST_CHAR_LIMIT ]] && LIST_LABEL="${LIST_LABEL:0:$LIST_CHAR_LIMIT}..."
ICON_TASK=$'\xef\x82\xae'

idle_chip() {
    local idle text_bg
    idle=$(tmux show -gqv @doit-color-idle 2>/dev/null)
    text_bg=$(tmux show -gqv @doit-color-text-bg 2>/dev/null)
    [[ -n "$idle" ]] && tmux set -gq @doit-todo-fg "$idle"
    [[ -n "$text_bg" ]] && tmux set -gq @doit-todo-text-bg "$text_bg"
    tmux set -gq @doit-todo-icon "$ICON_TASK"
    echo "${LIST_LABEL}: no active"
    exit 0
}

if ! command -v jq &> /dev/null; then
    idle_chip
fi

if [[ ! -f "$TODO_LIST_PATH" ]]; then
    idle_chip
fi

todo_json=$(jq -r '[.todos[] | select(.in_progress == true)][0] // empty | "\(.priorities // "")\t\(.text)"' "$TODO_LIST_PATH" 2>/dev/null)

if [[ -z "$todo_json" ]]; then
    idle_chip
fi

todo_priority=$(printf '%s' "$todo_json" | cut -f1)
todo_text=$(printf '%s' "$todo_json" | cut -f2-)

case "$todo_priority" in
    critical)  COLOR=$(tmux show -gqv @doit-color-critical 2>/dev/null) ;;
    urgent)    COLOR=$(tmux show -gqv @doit-color-urgent 2>/dev/null) ;;
    important) COLOR=$(tmux show -gqv @doit-color-important 2>/dev/null) ;;
    *)         COLOR=$(tmux show -gqv @doit-color-active 2>/dev/null) ;;
esac
[[ -n "$COLOR" ]] && tmux set -gq @doit-todo-fg "$COLOR"
TEXT_BG=$(tmux show -gqv @doit-color-text-bg 2>/dev/null)
[[ -n "$TEXT_BG" ]] && tmux set -gq @doit-todo-text-bg "$TEXT_BG"
tmux set -gq @doit-todo-icon "$ICON_TASK"

todo_text="${todo_text#"${todo_text%%[![:space:]]*}"}"
todo_text="${todo_text%"${todo_text##*[![:space:]]}"}"
todo_text="${todo_text#claude: }"
# the twin label serves the list views; in a narrow chip it pushes the task out
owed_re='^(.*)owed in [^ ]+ #[0-9]+: (.*)$'
[[ $todo_text =~ $owed_re ]] && todo_text="${BASH_REMATCH[1]}owed: ${BASH_REMATCH[2]}"

if [[ ${#todo_text} -gt $CHAR_LIMIT ]]; then
    todo_text="${todo_text:0:$CHAR_LIMIT}..."
fi

printf '%s: %s\n' "$LIST_LABEL" "$todo_text"
