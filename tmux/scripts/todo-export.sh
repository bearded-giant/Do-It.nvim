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
        # child items nest as an indented markdown list under their parent
        def pad($d):
            if $d == 0 then . else
                ([range($d)] | map("  ") | add) as $p
                | split("\n") | map(if . == "" then "" else $p + . end) | join("\n")
            end;
        def item:
            (.text // "") as $t |
            ((.description // "") | strip_footer | trim) as $d |
            ($t | split("\n")) as $tl |
            "- [ ] " + $tl[0]
            + (if ($tl | length) > 1 then "\n" + ($tl[1:] | join("\n") | indent) else "" end)
            + (if $d == "" then "" else "\n\n" + ($d | indent) end);
        def by_key: [prio_rank, (if .in_progress then 0 else 1 end), .order_index];
        # tree order over the pending set (mirrors export_markdown.lua nest()):
        # a child rides with its parent into the parent'"'"'s section, a child whose
        # parent is done or missing is a root, a parent cycle is still emitted
        def nest:
            . as $all
            | (map(select(.id != null) | {key: .id, value: true}) | from_entries) as $ids
            | def kids($pid; $d; $rank):
                [$all[] | select(.parent_id == $pid and .id != $pid)] | sort_by(by_key)
                | map(. as $k | [$k + {depth: $d, rank: $rank}] + kids($k.id; $d + 1; $rank)) | add // [];
            ([.[] | select(.parent_id == null or $ids[.parent_id] == null or .parent_id == .id)]
                | sort_by(by_key)
                | map(. as $r | [$r + {depth: 0, rank: ($r | prio_rank)}] + kids($r.id; 1; ($r | prio_rank)))
                | add // []) as $rows
            | ($rows | map(.id)) as $seen
            | $rows + [$all[] | select([.id] | inside($seen) | not) | . + {depth: 0, rank: prio_rank}];

        ["Critical", "Urgent", "Important", "Default"] as $labels |
        ([.todos[] | select(.done != true)]
            | nest
            | group_by(.rank)
            | map("## " + $labels[.[0].rank] + "\n\n" + (map(.depth as $d | item | pad($d)) | join("\n\n")))
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
