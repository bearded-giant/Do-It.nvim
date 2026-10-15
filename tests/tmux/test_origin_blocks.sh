#!/bin/bash

# origin split in the tmux UI: open todos render in a Mine block then a Claude
# block, each subtree following its root's origin, with banner rows only when
# both blocks have open items. section-jump stops on the banners and K/J never
# swaps across the boundary.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_harness.sh"

SCRIPTS="$SCRIPT_DIR/../../tmux/scripts"
DATA="$TEST_TMPDIR/data"
mkdir -p "$DATA/lists"
echo '{"active_list":"orig"}' > "$DATA/session.json"
LIST="$DATA/lists/orig.json"

cat > "$LIST" <<'JSON'
{
  "todos": [
    {"id":"M1","text":"plain mine","done":false,"in_progress":false,"order_index":1,"priorities":"urgent"},
    {"id":"M1d","text":"done child","done":true,"in_progress":false,"order_index":2,"parent_id":"M1","completed_at":10},
    {"id":"M2","text":"[[note]] x","done":false,"in_progress":false,"order_index":3},
    {"id":"M3","text":"1.5x faster","done":false,"in_progress":false,"order_index":4},
    {"id":"M4","text":"5. x","source":"user","done":false,"in_progress":false,"order_index":5},
    {"id":"M5","text":"  3.buy milk","done":false,"in_progress":false,"order_index":6},
    {"id":"MI","text":"mine running","done":false,"in_progress":true,"order_index":7},
    {"id":"C1","text":"claude: x","done":false,"in_progress":false,"order_index":10},
    {"id":"C1a","text":"plain child","done":false,"in_progress":false,"order_index":11,"parent_id":"C1"},
    {"id":"C2","text":"[gate] 3. x","done":false,"in_progress":false,"order_index":12},
    {"id":"C3","text":"4. x","done":false,"in_progress":false,"order_index":13},
    {"id":"C4","text":"plain twin","twin":{"list":"daily","id":"T"},"done":false,"in_progress":false,"order_index":14},
    {"id":"C5","text":"plain from mcp","source":"mcp","done":false,"in_progress":false,"order_index":15},
    {"id":"CI","text":"claude: running","done":false,"in_progress":true,"order_index":16},
    {"id":"DM","text":"mine finished","done":true,"in_progress":false,"order_index":20,"completed_at":100},
    {"id":"DC","text":"claude: finished","done":true,"in_progress":false,"order_index":21,"completed_at":200}
  ],
  "_metadata": {"name":"orig"}
}
JSON

run_format() {
    env -u TMUX DOIT_DATA_DIR="$DATA" bash "$SCRIPTS/todo-interactive.sh" --format 2>/dev/null \
        | sed 's/\x1b\[[0-9;]*m//g'
}

# one token per rendered line: the row id, BANNER <label> <count>, HR, or the
# trimmed text of a header/blank line
shape() {
    sed -e 's/─/-/g' \
        -E -e 's/^-- (Mine|Claude) -{3,} ([0-9]+)$/BANNER \1 \2/' \
        -e 's/^-+$/HR/' \
        -e 's/.*\[([^]]+)\]$/\1/' \
        -e 's/^[[:space:]]+//' -e 's/[[:space:]]+$//' <<< "$1" | paste -sd ' ' -
}

line_of() { grep -nF "[$1]" <<< "$FORMAT" | head -1 | cut -d: -f1; }
banner_line() { grep -nE "^── $1 " <<< "$FORMAT" | head -1 | cut -d: -f1; }
ascii() { sed 's/─/-/g' <<< "$1"; }

describe "todo-interactive.sh --format: Mine / Claude blocks"

FORMAT=$(run_format)
MINE_BANNER=$(ascii "$(grep -E '^── Mine ' <<< "$FORMAT")")
CLAUDE_BANNER=$(ascii "$(grep -E '^── Claude ' <<< "$FORMAT")")
HR=$(ascii "$(grep -E '^─+$' <<< "$FORMAT" | head -1)")

it "classifies each root into its block, mine first, with the done section unchanged"
assert_eq \
    " BANNER Mine 6 MI  Urgent M1 M1d  Default M2 M3 M4 M5  BANNER Claude 7 CI  Default C1 C1a C2 C3 C4 C5  Notes (no notes)  HR  DC DM" \
    "$(shape "$FORMAT")"

it "the Mine banner fills the done-rule width with at least 3 fill chars"
assert_eq "${#HR}" "${#MINE_BANNER}"
assert_eq "1" "$(grep -cE '^-- Mine -{3,} 6$' <<< "$MINE_BANNER")"

it "the Claude banner fills the done-rule width"
assert_eq "${#HR}" "${#CLAUDE_BANNER}"
assert_eq "1" "$(grep -cE '^-- Claude -{3,} 7$' <<< "$CLAUDE_BANNER")"

it "a single blank line separates the Mine block from the Claude banner"
CB=$(banner_line Claude)
assert_eq "" "$(sed -n "$(( CB - 1 ))p" <<< "$FORMAT")"
assert_eq "$(( CB - 2 ))" "$(line_of M5)"

it "a plain child of a claude root stays in the Claude block"
assert_eq "$(( $(line_of C1) + 1 ))" "$(line_of C1a)"

it "a claude in-progress item renders at the top of the Claude block"
assert_eq "$(( CB + 1 ))" "$(line_of CI)"

it "a mine in-progress item renders at the top of the Mine block"
assert_eq "$(( $(banner_line Mine) + 1 ))" "$(line_of MI)"

it "banner rows carry no [id]"
assert_eq "0" "$(grep -E '^── (Mine|Claude) ' <<< "$FORMAT" | grep -cE '\]$')"

describe "section-jump.sh: banner stops"

jump() { env -u TMUX DOIT_DATA_DIR="$DATA" bash "$SCRIPTS/section-jump.sh" "$@" 2>/dev/null; }

it "down from the top lands on the Mine banner"
assert_eq "pos($(banner_line Mine))" "$(jump down 0)"

it "down from the blank above the Claude banner lands on it"
assert_eq "pos($CB)" "$(jump down $(( CB - 2 )))"

it "up from the first Claude row lands on the Claude banner"
assert_eq "pos($CB)" "$(jump up "$CB")"

describe "todo-move.sh: never swaps across the Mine/Claude boundary"

order_of() { jq -r --arg id "$1" '.todos[] | select(.id == $id) | .order_index' "$LIST"; }
move() { env -u TMUX DOIT_DATA_DIR="$DATA" bash "$SCRIPTS/todo-move.sh" "$@" > /dev/null 2>&1; }

move up "claude: x [C1]"
it "the first claude default root does not swap up with the last mine default root"
assert_eq "10" "$(order_of C1)"
assert_eq "6" "$(order_of M5)"

move down "3.buy milk [M5]"
it "the last mine default root does not swap down with the first claude root"
assert_eq "6" "$(order_of M5)"
assert_eq "10" "$(order_of C1)"

move down "claude: x [C1]"
it "a claude root still swaps with the next claude root"
assert_eq "12" "$(order_of C1)"
assert_eq "10" "$(order_of C2)"

describe "todo-interactive.sh --format: one origin only"

single_origin_list() {
    cat > "$LIST" <<JSON
{
  "todos": [
    {"id":"I","text":"$1running","done":false,"in_progress":true,"order_index":1},
    {"id":"U","text":"$1urgent","done":false,"in_progress":false,"order_index":2,"priorities":"urgent"},
    {"id":"D","text":"$1default","done":false,"in_progress":false,"order_index":3},
    {"id":"X","text":"$2finished","done":true,"in_progress":false,"order_index":4,"completed_at":5}
  ],
  "_metadata": {"name":"orig"}
}
JSON
}

EXPECTED_SINGLE=" I  Urgent U  Default D  Notes (no notes)  HR  X"

single_origin_list "" "claude: "
FORMAT=$(run_format)
it "an all-mine list (done claude item aside) shows no banners"
assert_eq "0" "$(grep -cE '^── (Mine|Claude)' <<< "$FORMAT")"
it "an all-mine list keeps the unsplit layout"
assert_eq "$EXPECTED_SINGLE" "$(shape "$FORMAT")"

single_origin_list "claude: " ""
FORMAT=$(run_format)
it "an all-claude list (done mine item aside) shows no banners"
assert_eq "0" "$(grep -cE '^── (Mine|Claude)' <<< "$FORMAT")"
it "an all-claude list keeps the unsplit layout"
assert_eq "$EXPECTED_SINGLE" "$(shape "$FORMAT")"

report
