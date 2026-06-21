#!/bin/bash
# fzf bind helper: reorder a todo within its priority group and keep the cursor
# on it. Called from todo-interactive.sh via a `transform` bind for K/J reorder.
# Swaps order_index with the nearest same-group neighbor (same in_progress flag +
# same priority), then prints fzf actions: reload(format)+pos(new line of todo).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/get-active-list.sh"
unset DOIT_ACTIVE_LIST
TODO_LIST_PATH="$(get_active_list_path)"

DIRECTION="$1"
shift
LINE="$*"
TODO_ID=$(echo "$LINE" | grep -oE '\[[^]]+\]$' | tr -d '[]')

# only real todos reorder; notes/headers just keep the cursor put
if [[ -n "$TODO_ID" && "$TODO_ID" != note_* ]]; then
    case "$DIRECTION" in
        up)   OP='.order_index < $cur' ; PICK='max_by(.order_index)' ;;
        down) OP='.order_index > $cur' ; PICK='min_by(.order_index)' ;;
        *)    OP='' ;;
    esac
    if [[ -n "$OP" ]]; then
        jq --arg id "$TODO_ID" "
            (.todos[] | select(.id == \$id)) as \$me |
            (\$me.order_index) as \$cur |
            ([.todos[] | select(
                .done == false
                and ((.in_progress // false) == (\$me.in_progress // false))
                and ((.priorities // \"\") == (\$me.priorities // \"\"))
                and $OP)] | $PICK) as \$swap |
            if \$swap then
                .todos |= map(
                    if .id == \$id then .order_index = \$swap.order_index
                    elif .id == \$swap.id then .order_index = \$cur
                    else . end)
            else . end |
            ._metadata.updated_at = (now | floor)
        " "$TODO_LIST_PATH" > "${TODO_LIST_PATH}.tmp" && mv "${TODO_LIST_PATH}.tmp" "$TODO_LIST_PATH"
    fi
fi

# locate the (possibly moved) row in the freshly formatted list so fzf can
# re-anchor the cursor on it. reload-sync (not reload) so pos() runs AFTER the
# list reloads -- async reload resets the cursor to the top, dropping pos().
[[ -z "$TODO_ID" ]] && exit 0
N=$("$SCRIPT_DIR/todo-interactive.sh" --format \
    | sed 's/\x1b\[[0-9;]*m//g' \
    | grep -nF "[$TODO_ID]" | head -1 | cut -d: -f1)
[[ -z "$N" ]] && exit 0
echo "reload-sync($SCRIPT_DIR/todo-interactive.sh --format)+pos($N)"
