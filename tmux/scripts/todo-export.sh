#!/bin/bash

# Export the active list's non-completed todos to markdown.
# usage: todo-export.sh [out_path] [list_json_path]
# Output format must stay byte-identical to the nvim exporter
# (lua/doit/modules/todos/state/export_markdown.lua).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/get-active-list.sh"

if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed" >&2
    exit 1
fi

OUT_PATH="$1"
LIST_PATH="${2:-$(get_active_list_path)}"
LIST_NAME="$(basename "$LIST_PATH" .json)"

if [[ ! -f "$LIST_PATH" ]]; then
    echo "Error: list not found: $LIST_PATH" >&2
    exit 1
fi

export_dir() {
    local dir
    dir=$(tmux show-option -gqv "@doit-export-dir" 2>/dev/null)
    dir="${dir:-$PWD}"
    echo "${dir/#\~/$HOME}"
}

if [[ -z "$OUT_PATH" ]]; then
    OUT_PATH="$(export_dir)/${LIST_NAME}.md"
fi
OUT_PATH="${OUT_PATH/#\~/$HOME}"

build_markdown() {
    jq -r --arg list "$LIST_NAME" --arg now "$(date '+%Y-%m-%d %H:%M')" '
        def strip_footer: (. // "") | sub("\n*----------\nlast [a-z]+:(.|\n)*$"; "");
        def trim: sub("^\\s+"; "") | sub("\\s+$"; "");
        def prio_rank:
            if .priorities == "critical" then 0
            elif .priorities == "urgent" then 1
            elif .priorities == "important" then 2
            else 3 end;
        def indent: split("\n") | map(if . == "" then "" else "  " + . end) | join("\n");
        def item:
            (.text // "") as $t |
            ((.description // "") | strip_footer | trim) as $d |
            ($t | split("\n")) as $tl |
            "- [ ] " + $tl[0]
            + (if ($tl | length) > 1 then "\n" + ($tl[1:] | join("\n") | indent) else "" end)
            + (if $d == "" then "" else "\n\n" + ($d | indent) end);

        ["Critical", "Urgent", "Important", "Default"] as $labels |
        ([.todos[] | select(.done != true)]
            | sort_by(prio_rank, (if .in_progress then 0 else 1 end), .order_index)
            | group_by(prio_rank)
            | map("## " + $labels[.[0] | prio_rank] + "\n\n" + (map(item) | join("\n\n")))
        ) as $sections |
        # jq -r appends the final newline, so no trailing "\n" here
        "# " + $list + "\n\n_exported " + $now + "_\n\n"
        + (if ($sections | length) == 0 then "_no pending items_" else ($sections | join("\n\n")) end)
    ' "$LIST_PATH"
}

mkdir -p "$(dirname "$OUT_PATH")" 2>/dev/null
if ! build_markdown > "$OUT_PATH"; then
    echo "Error: export failed" >&2
    exit 1
fi

echo "$OUT_PATH"
