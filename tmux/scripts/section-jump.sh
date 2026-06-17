#!/bin/bash

# Emit an fzf `pos(N)` action to jump the cursor to the next/previous section
# header in the interactive todo list. Sections = the named headers rendered by
# format_todos: Critical / Urgent / Important / Default / Notes.
#
# Usage (from an fzf transform bind): section-jump.sh <down|up> {n}
#   {n} = fzf's current 0-based item index.

dir="$1"
cur0="$2"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cur=$(( cur0 + 1 ))  # 1-based line/item number

# header line numbers (1-based) in the current render, recomputed fresh so this
# stays correct after reorders that shifted positions
H=( $("$SCRIPT_DIR/todo-interactive.sh" --format 2>/dev/null \
        | sed 's/\x1b\[[0-9;]*m//g' \
        | grep -nxE 'Critical|Urgent|Important|Default|Notes' \
        | cut -d: -f1) )

[ ${#H[@]} -eq 0 ] && exit 0

if [ "$dir" = "down" ]; then
    for h in "${H[@]}"; do
        if [ "$h" -gt "$cur" ]; then echo "pos($h)"; exit 0; fi
    done
    echo "pos(${H[0]})"  # wrap to first section
else
    prev=""
    for h in "${H[@]}"; do
        if [ "$h" -lt "$cur" ]; then prev="$h"; fi
    done
    if [ -n "$prev" ]; then
        echo "pos($prev)"
    else
        echo "pos(${H[$(( ${#H[@]} - 1 ))]})"  # wrap to last section
    fi
fi
