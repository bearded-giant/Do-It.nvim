#!/bin/bash
# fzf bind helper: reorder a todo within its section and keep the cursor on it.
# Called from todo-interactive.sh via a `transform` bind for K/J reorder.
# A Sequence-section row swaps `sequence` with the nearest sequenced SIBLING
# (crossing priority); any other row swaps order_index with the nearest sibling
# of the same in_progress flag and priority. Then prints fzf actions:
# reload(format)+pos(new line of todo). Siblings only: a child rides with its
# parent in the tree order, so swapping with another parent's child moves nothing
# and swapping two siblings moves their whole subtrees.

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
        up)   OP='.[$f] < $cur' ; PICK='max_by(.[$f])' ;;
        down) OP='.[$f] > $cur' ; PICK='min_by(.[$f])' ;;
        *)    OP='' ;;
    esac
    if [[ -n "$OP" ]]; then
        jq --arg id "$TODO_ID" "
            def seqd: (.sequence | type) == \"number\" and (.done | not) and (.in_progress | not);
            (.todos[] | select(.id == \$id)) as \$me |
            (\$me | seqd) as \$mseq |
            (if \$mseq then \"sequence\" else \"order_index\" end) as \$f |
            (\$me[\$f]) as \$cur |
            ([.todos[] | select(
                .done == false
                and ((.parent_id // \"\") == (\$me.parent_id // \"\"))
                and (seqd == \$mseq)
                and (\$mseq or (
                    ((.in_progress // false) == (\$me.in_progress // false))
                    and ((.priorities // \"\") == (\$me.priorities // \"\"))))
                and $OP)] | $PICK) as \$swap |
            if \$swap then
                .todos |= map(
                    if .id == \$id then .[\$f] = \$swap[\$f]
                    elif .id == \$swap.id then .[\$f] = \$cur
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
