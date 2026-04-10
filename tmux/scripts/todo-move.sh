#!/bin/bash
# fzf bind helper: swap todo order_index in JSON
# called from todo-interactive.sh fzf --bind for K/J reorder

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/get-active-list.sh"
unset DOIT_ACTIVE_LIST
TODO_LIST_PATH="$(get_active_list_path)"

DIRECTION="$1"
shift
LINE="$*"
TODO_ID=$(echo "$LINE" | grep -oE '\[[^]]+\]$' | tr -d '[]')
[[ -z "$TODO_ID" ]] && exit 0

case "$DIRECTION" in
    up)
        jq --arg id "$TODO_ID" '
            (.todos[] | select(.id == $id) | .order_index) as $cur |
            ([.todos[] | select(.done == false and .order_index < $cur)] | max_by(.order_index)) as $swap |
            if $swap then
                .todos |= map(
                    if .id == $id then .order_index = $swap.order_index
                    elif .id == $swap.id then .order_index = $cur
                    else . end)
            else . end |
            ._metadata.updated_at = (now | floor)
        ' "$TODO_LIST_PATH" > "${TODO_LIST_PATH}.tmp" && mv "${TODO_LIST_PATH}.tmp" "$TODO_LIST_PATH"
        ;;
    down)
        jq --arg id "$TODO_ID" '
            (.todos[] | select(.id == $id) | .order_index) as $cur |
            ([.todos[] | select(.done == false and .order_index > $cur)] | min_by(.order_index)) as $swap |
            if $swap then
                .todos |= map(
                    if .id == $id then .order_index = $swap.order_index
                    elif .id == $swap.id then .order_index = $cur
                    else . end)
            else . end |
            ._metadata.updated_at = (now | floor)
        ' "$TODO_LIST_PATH" > "${TODO_LIST_PATH}.tmp" && mv "${TODO_LIST_PATH}.tmp" "$TODO_LIST_PATH"
        ;;
esac
