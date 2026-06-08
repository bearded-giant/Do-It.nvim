#!/bin/bash

# Get the current in-progress todo from active list.
# When nothing is in_progress, keep the chip's icon + width visible
# (neutral color, blank text) so layout doesn't shift —
# the user makes a todo active via nvim `c` / tmux `s` to populate it.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/get-active-list.sh"

TODO_LIST_PATH="$(get_active_list_path)"
CHAR_LIMIT=25
ICON_TASK=$'\xef\x82\xae'

idle_chip() {
    local idle text_bg
    idle=$(tmux show -gqv @doit-color-idle 2>/dev/null)
    text_bg=$(tmux show -gqv @doit-color-text-bg 2>/dev/null)
    [[ -n "$idle" ]] && tmux set -gq @doit-todo-fg "$idle"
    [[ -n "$text_bg" ]] && tmux set -gq @doit-todo-text-bg "$text_bg"
    tmux set -gq @doit-todo-icon "$ICON_TASK"
    echo "< NO ACTIVE TODO >"
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

if [[ ${#todo_text} -gt $CHAR_LIMIT ]]; then
    todo_text="${todo_text:0:$CHAR_LIMIT}..."
fi

printf '%s\n' "$todo_text"
