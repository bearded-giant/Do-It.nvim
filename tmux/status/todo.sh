#!/bin/bash

# Status bar module for displaying current todo from do-it.nvim
# This file should be sourced by tmux theme scripts (e.g., bearded-giant-tmux)

# Resolve scripts directory from environment or relative path
if [[ -n "$DOIT_SCRIPTS_DIR" ]]; then
    SCRIPTS_DIR="$DOIT_SCRIPTS_DIR"
else
    SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)"
fi

# Source the helper for dynamic list path
source "$SCRIPTS_DIR/get-active-list.sh"

TODO_LIST_PATH="$(get_active_list_path)"
ACTIVE_LIST_NAME="$(get_active_list_name)"
CHAR_LIMIT="${DOIT_CHAR_LIMIT:-25}"

get_todo_status() {
    if ! command -v jq &> /dev/null; then
        echo "gray|No jq"
        return
    fi

    if [[ ! -f "$TODO_LIST_PATH" ]]; then
        echo "gray|No todos"
        return
    fi

    # get in-progress todo first
    local todo_text=$(jq -r '.todos[] | select(.in_progress == true) | .text' "$TODO_LIST_PATH" 2>/dev/null | head -1)
    local status_color="green"

    # fallback to first pending todo
    if [[ -z "$todo_text" ]]; then
        todo_text=$(jq -r '.todos | sort_by(.order_index) | .[] | select(.done == false) | .text' "$TODO_LIST_PATH" 2>/dev/null | head -1)
        status_color="yellow"

        if [[ -z "$todo_text" ]]; then
            echo "blue|All done!"
            return
        fi
    fi

    # trim whitespace
    todo_text=$(echo "$todo_text" | xargs)

    if [[ ${#todo_text} -gt $CHAR_LIMIT ]]; then
        todo_text="${todo_text:0:$CHAR_LIMIT}..."
    fi

    echo "${status_color}|${todo_text}"
}

show_todo() {
    local index=$1
    local icon
    local color
    local text
    local module

    local result=$(get_todo_status)
    local todo_color=$(echo "$result" | cut -d'|' -f1)
    local todo_text=$(echo "$result" | cut -d'|' -f2-)
    local todo_text_trimmed=$(echo "$todo_text" | xargs)

    if [[ "$todo_text_trimmed" == *"All done"* ]]; then
        icon=""
    else
        icon=""
    fi

    case "$todo_color" in
    "green") color="$thm_green" ;;
    "yellow") color="$thm_yellow" ;;
    "blue") color="$thm_blue" ;;
    "gray") color="$thm_gray" ;;
    *) color="$thm_fg" ;;
    esac

    # use todo-exec.sh for dynamic status text, include list name
    local script_path="${SCRIPTS_DIR}/todo-exec.sh"
    local list_name="${ACTIVE_LIST_NAME:-daily}"
    text="  [${list_name}] #(${script_path})  "

    module=$(build_status_module "$index" "$icon" "$color" "$text")

    echo "$module"
}

# direct execution for testing
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    get_todo_status
fi
