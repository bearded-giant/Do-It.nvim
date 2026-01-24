#!/bin/bash

# list manager for doit tmux integration
# create, rename, delete lists

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/get-active-list.sh"

if ! command -v jq &> /dev/null; then
    echo "Error: jq is required"
    exit 1
fi

if ! command -v fzf &> /dev/null; then
    echo "Error: fzf is required"
    exit 1
fi

CURRENT_LIST=$(get_active_list_name)

# colors
COLOR_GREEN=$'\e[1;32m'
COLOR_YELLOW=$'\e[1;33m'
COLOR_RED=$'\e[1;31m'
COLOR_RESET=$'\e[0m'

preview_list() {
    local list_file="$LISTS_DIR/${1}.json"
    if [[ -f "$list_file" ]]; then
        local total=$(jq '.todos | length' "$list_file" 2>/dev/null || echo 0)
        local pending=$(jq '[.todos[] | select(.done == false)] | length' "$list_file" 2>/dev/null || echo 0)
        local in_progress=$(jq '[.todos[] | select(.in_progress == true)] | length' "$list_file" 2>/dev/null || echo 0)
        echo "Total: $total  Pending: $pending  In Progress: $in_progress"
        echo ""
        jq -r '.todos | sort_by(.order_index) | .[0:5] | .[] | .text | split("\n")[0][0:50]' "$list_file" 2>/dev/null | while read -r line; do
            echo "• $line"
        done
    fi
}
export -f preview_list
export LISTS_DIR

create_list() {
    echo ""
    echo -n "New list name: "
    read -r NEW_NAME

    if [[ -z "$NEW_NAME" ]]; then
        echo "Cancelled"
        return
    fi

    # sanitize name (alphanumeric, dash, underscore only)
    SAFE_NAME=$(echo "$NEW_NAME" | tr ' ' '_' | tr -cd '[:alnum:]_-')

    if [[ -f "$LISTS_DIR/${SAFE_NAME}.json" ]]; then
        echo "${COLOR_RED}Error: List '$SAFE_NAME' already exists${COLOR_RESET}"
        sleep 1
        return
    fi

    # create new list with empty structure
    cat > "$LISTS_DIR/${SAFE_NAME}.json" << EOF
{
  "todos": [],
  "_metadata": {
    "created_at": $(date +%s),
    "updated_at": $(date +%s)
  }
}
EOF

    echo "${COLOR_GREEN}Created list: $SAFE_NAME${COLOR_RESET}"

    echo -n "Switch to new list? (Y/n): "
    read -n 1 -r SWITCH
    echo
    if [[ ! "$SWITCH" =~ ^[Nn]$ ]]; then
        set_active_list "$SAFE_NAME"
        echo "Switched to: $SAFE_NAME"
    fi
    sleep 1
}

rename_list() {
    local old_name="$1"

    if [[ "$old_name" == "$CURRENT_LIST" ]]; then
        echo "${COLOR_YELLOW}Warning: Renaming active list${COLOR_RESET}"
    fi

    echo -n "New name for '$old_name': "
    read -r NEW_NAME

    if [[ -z "$NEW_NAME" ]]; then
        echo "Cancelled"
        return
    fi

    SAFE_NAME=$(echo "$NEW_NAME" | tr ' ' '_' | tr -cd '[:alnum:]_-')

    if [[ -f "$LISTS_DIR/${SAFE_NAME}.json" ]]; then
        echo "${COLOR_RED}Error: List '$SAFE_NAME' already exists${COLOR_RESET}"
        sleep 1
        return
    fi

    mv "$LISTS_DIR/${old_name}.json" "$LISTS_DIR/${SAFE_NAME}.json"

    # update session if this was active list
    if [[ "$old_name" == "$CURRENT_LIST" ]]; then
        set_active_list "$SAFE_NAME"
    fi

    echo "${COLOR_GREEN}Renamed: $old_name -> $SAFE_NAME${COLOR_RESET}"
    sleep 1
}

delete_list() {
    local list_name="$1"

    if [[ "$list_name" == "$CURRENT_LIST" ]]; then
        echo "${COLOR_RED}Cannot delete active list. Switch to another list first.${COLOR_RESET}"
        sleep 1
        return
    fi

    local todo_count=$(jq '.todos | length' "$LISTS_DIR/${list_name}.json" 2>/dev/null || echo 0)

    echo -n "${COLOR_RED}Delete '$list_name' ($todo_count todos)? Type 'yes' to confirm: ${COLOR_RESET}"
    read -r CONFIRM

    if [[ "$CONFIRM" == "yes" ]]; then
        rm -f "$LISTS_DIR/${list_name}.json"
        echo "${COLOR_GREEN}Deleted: $list_name${COLOR_RESET}"
    else
        echo "Cancelled"
    fi
    sleep 1
}

# main loop
while true; do
    CURRENT_LIST=$(get_active_list_name)

    # format list with active indicator
    LIST_DISPLAY=$(get_available_lists | while read -r name; do
        if [[ "$name" == "$CURRENT_LIST" ]]; then
            echo "* $name (active)"
        else
            echo "  $name"
        fi
    done)

    SELECTION=$(echo "$LIST_DISPLAY" | fzf --ansi \
        --header="
 List Manager - Active: $CURRENT_LIST
─────────────────────────────────────────
 n: New    r: Rename    d: Delete
 ENTER: Switch to list
─────────────────────────────────────────
" \
        --prompt="List > " \
        --height=60% \
        --layout=reverse \
        --expect=n,r,d,enter,q \
        --preview='bash -c "preview_list \$(echo {} | sed \"s/^[* ]*//\" | sed \"s/ (active)\$//\")"' \
        --preview-window=right:50%:wrap)

    KEY=$(echo "$SELECTION" | head -1)
    LIST_LINE=$(echo "$SELECTION" | tail -1)

    # extract list name from line
    SELECTED_LIST=$(echo "$LIST_LINE" | sed 's/^[* ]*//' | sed 's/ (active)$//')

    case "$KEY" in
        "q"|"")
            break
            ;;
        "n")
            create_list
            ;;
        "r")
            if [[ -n "$SELECTED_LIST" ]]; then
                rename_list "$SELECTED_LIST"
            fi
            ;;
        "d")
            if [[ -n "$SELECTED_LIST" ]]; then
                delete_list "$SELECTED_LIST"
            fi
            ;;
        "enter")
            if [[ -n "$SELECTED_LIST" && "$SELECTED_LIST" != "$CURRENT_LIST" ]]; then
                set_active_list "$SELECTED_LIST"
                break
            fi
            ;;
    esac
done
