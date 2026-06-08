#!/bin/bash

# Status bar module for the current in-progress todo from do-it.nvim.
# When nothing is in_progress the icon stays visible in a neutral idle color
# (placement preserved, text blank) so the user has a clear slot to claim
# via nvim `c` / tmux `s`.
# This file should be sourced by tmux theme scripts (e.g., bearded-giant-tmux).

if [[ -n "$DOIT_SCRIPTS_DIR" ]]; then
    SCRIPTS_DIR="$DOIT_SCRIPTS_DIR"
else
    SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)"
fi

source "$SCRIPTS_DIR/get-active-list.sh"

TODO_LIST_PATH="$(get_active_list_path)"
ACTIVE_LIST_NAME="$(get_active_list_name)"
CHAR_LIMIT="${DOIT_CHAR_LIMIT:-20}"
ICON_TASK=$'\xef\x82\xae'

get_active_todo() {
    if ! command -v jq &> /dev/null; then
        echo ""
        return
    fi

    if [[ ! -f "$TODO_LIST_PATH" ]]; then
        echo ""
        return
    fi

    local todo_text
    todo_text=$(jq -r '.todos[] | select(.in_progress == true) | .text' "$TODO_LIST_PATH" 2>/dev/null | head -1)
    todo_text=$(echo "$todo_text" | xargs)

    if [[ -z "$todo_text" ]]; then
        echo ""
        return
    fi

    if [[ ${#todo_text} -gt $CHAR_LIMIT ]]; then
        todo_text="${todo_text:0:$CHAR_LIMIT}..."
    fi

    echo "$todo_text"
}

show_todo() {
    local index=$1

    tmux set -gq @doit-color-active "$thm_green"
    tmux set -gq @doit-color-idle "$thm_blue"
    tmux set -gq @doit-color-text-bg "$thm_gray"
    tmux set -gq @doit-color-critical "$thm_red"
    tmux set -gq @doit-color-urgent "$thm_yellow"
    tmux set -gq @doit-color-important "$thm_blue"

    local initial_text
    initial_text=$(get_active_todo)
    if [[ -n "$initial_text" ]]; then
        tmux set -gq @doit-todo-fg "$thm_green"
    else
        tmux set -gq @doit-todo-fg "$thm_blue"
    fi
    tmux set -gq @doit-todo-icon "$ICON_TASK"
    tmux set -gq @doit-todo-text-bg "$thm_gray"

    local color="#{@doit-todo-fg}"
    local icon="#{@doit-todo-icon}"
    local text_bg="#{@doit-todo-text-bg}"
    local script_path="${SCRIPTS_DIR}/todo-exec.sh"

    # custom renderer — mirrors theme's status_fill=icon geometry but with
    # dynamic bg refs so the chip can fully collapse into $thm_bg when empty.
    local left_sep_style="#[fg=${color},bg=${thm_bg},nobold,nounderscore,noitalics]"
    local icon_style="#[fg=${thm_bg},bg=${color},nobold,nounderscore,noitalics]"
    local text_style="#[fg=${thm_fg},bg=${text_bg}]"
    local right_sep_style="#[fg=${text_bg},bg=${thm_bg},nobold,nounderscore,noitalics]"

    local module="${left_sep_style}${status_left_separator}${icon_style}${icon} ${text_style} #(${script_path}) ${right_sep_style}${status_right_separator}"

    echo "$module"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    get_active_todo
fi
