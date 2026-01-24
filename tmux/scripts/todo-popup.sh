#!/bin/bash

# Simple todo list viewer/manager for tmux popup

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/get-active-list.sh"

TODO_LIST_PATH="$(get_active_list_path)"
ACTIVE_LIST_NAME="$(get_active_list_name)"

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed"
    exit 1
fi

# Check if the list file exists
if [[ ! -f "$TODO_LIST_PATH" ]]; then
    echo "Error: Todo list '$ACTIVE_LIST_NAME' not found"
    exit 1
fi

# Colors and formatting
BOLD='\033[1m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
GRAY='\033[90m'
RESET='\033[0m'

# Display header
echo -e "${BLUE}${BOLD}╭─────────────────────────────────────────────╮${RESET}"
echo -e "${BLUE}${BOLD}│         Do-It: ${ACTIVE_LIST_NAME}$(printf '%*s' $((27 - ${#ACTIVE_LIST_NAME})) '')│${RESET}"
echo -e "${BLUE}${BOLD}╰─────────────────────────────────────────────╯${RESET}"
echo ""

# Display statistics
TOTAL=$(jq '.todos | length' "$TODO_LIST_PATH")
DONE=$(jq '[.todos[] | select(.done == true)] | length' "$TODO_LIST_PATH")
IN_PROGRESS=$(jq '[.todos[] | select(.in_progress == true)] | length' "$TODO_LIST_PATH")
PENDING=$(jq '[.todos[] | select(.done == false and .in_progress != true)] | length' "$TODO_LIST_PATH")

echo -e "${BOLD}Stats:${RESET} Total: $TOTAL | Done: ${GREEN}$DONE${RESET} | In Progress: ${YELLOW}$IN_PROGRESS${RESET} | Pending: $PENDING"
echo -e "─────────────────────────────────────────────"
echo ""

# Display todos
echo -e "${BOLD}Tasks:${RESET}"
echo ""

# Show in-progress todos first
if [[ $IN_PROGRESS -gt 0 ]]; then
    echo -e "${YELLOW}▶ In Progress:${RESET}"
    jq -r '.todos[] | select(.in_progress == true) | "  • \(.text)"' "$TODO_LIST_PATH" | while IFS= read -r line; do
        echo -e "${GREEN}$line${RESET}"
    done
    echo ""
fi

# Show pending todos
PENDING_COUNT=$(jq '[.todos[] | select(.done == false and .in_progress != true)] | length' "$TODO_LIST_PATH")
if [[ $PENDING_COUNT -gt 0 ]]; then
    echo -e "${BOLD}◯ Pending:${RESET}"
    jq -r '.todos | sort_by(.order_index) | .[] | select(.done == false and .in_progress != true) | "  • \(.text)"' "$TODO_LIST_PATH" | head -10 | while IFS= read -r line; do
        echo "$line"
    done

    if [[ $PENDING_COUNT -gt 10 ]]; then
        echo "  ... and $((PENDING_COUNT - 10)) more"
    fi
    echo ""
fi

# Show recently completed (last 3)
COMPLETED_COUNT=$(jq '[.todos[] | select(.done == true)] | length' "$TODO_LIST_PATH")
if [[ $COMPLETED_COUNT -gt 0 ]]; then
    echo -e "${GRAY}✓ Recently Completed:${RESET}"
    jq -r '.todos | sort_by(.order_index) | reverse | .[] | select(.done == true) | "  • \(.text)"' "$TODO_LIST_PATH" | head -3 | while IFS= read -r line; do
        echo -e "${GRAY}$line${RESET}"
    done
    echo ""
fi

# Show keybinding hints
echo -e "─────────────────────────────────────────────"
echo -e "${BOLD}Keybindings:${RESET}"
echo "  ${BOLD}T${RESET} - Open interactive manager"
echo "  ${BOLD}N${RESET} - Start next todo"
echo "  ${BOLD}X${RESET} - Toggle current todo done"
echo "  ${BOLD}ESC/q${RESET} - Close this window"
echo ""
echo "Press any key to close..."

# Wait for input
read -n 1 -s