#!/bin/bash

# sequence in the tmux UI: pending items with a sequence render in a Sequence
# section above the priority groups, ordered across priority, and K/J inside it
# swap sequence rather than order_index.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_harness.sh"

SCRIPTS="$SCRIPT_DIR/../../tmux/scripts"
DATA="$TEST_TMPDIR/data"
mkdir -p "$DATA/lists"
echo '{"active_list":"seq"}' > "$DATA/session.json"
LIST="$DATA/lists/seq.json"

cat > "$LIST" <<'JSON'
{
  "todos": [
    {"id":"C","text":"critical plain","done":false,"in_progress":false,"order_index":1,"priorities":"critical"},
    {"id":"S2","text":"second step","done":false,"in_progress":false,"order_index":2,"sequence":2},
    {"id":"S1","text":"first step","done":false,"in_progress":false,"order_index":3,"sequence":1,"priorities":"important"},
    {"id":"R","text":"running","done":false,"in_progress":true,"order_index":4,"sequence":3},
    {"id":"D","text":"plain default","done":false,"in_progress":false,"order_index":5}
  ],
  "_metadata": {"name":"seq"}
}
JSON

run_format() {
    env -u TMUX DOIT_DATA_DIR="$DATA" bash "$SCRIPTS/todo-interactive.sh" --format 2>/dev/null \
        | sed 's/\x1b\[[0-9;]*m//g'
}
line_of() { grep -nF "[$1]" <<< "$FORMAT" | head -1 | cut -d: -f1; }
header_line() { grep -nx "$1" <<< "$FORMAT" | head -1 | cut -d: -f1; }
seq_of() { jq -r --arg id "$1" '.todos[] | select(.id == $id) | .sequence // "none"' "$LIST"; }

describe "todo-interactive.sh --format: Sequence section"

FORMAT=$(run_format)

it "puts the Sequence header before the Critical header"
assert_eq "1" "$(( $(header_line Sequence) < $(header_line Critical) ))"

it "orders sequenced rows by sequence, not priority"
assert_eq "1" "$(( $(line_of S1) < $(line_of S2) && $(line_of S2) < $(line_of C) ))"

it "labels a sequenced row with its position after the priority glyph"
assert_eq "1" "$(grep -F '[S1]' <<< "$FORMAT" | grep -c '\* 1) first step')"

it "leaves an in-progress item out of the Sequence section"
assert_eq "1" "$(( $(line_of R) < $(header_line Sequence) ))"

describe "todo-move.sh: Sequence reorder"

env -u TMUX DOIT_DATA_DIR="$DATA" bash "$SCRIPTS/todo-move.sh" down "first step [S1]" > /dev/null 2>&1

it "moving down swaps sequence with the next sequenced item across priority"
assert_eq "2" "$(seq_of S1)"
assert_eq "1" "$(seq_of S2)"

it "leaves order_index alone on a sequence swap"
assert_eq "3" "$(jq -r '.todos[] | select(.id == "S1") | .order_index' "$LIST")"

env -u TMUX DOIT_DATA_DIR="$DATA" bash "$SCRIPTS/todo-move.sh" up "plain default [D]" > /dev/null 2>&1

it "an unsequenced default item does not swap into the Sequence section"
assert_eq "none" "$(seq_of D)"
assert_eq "5" "$(jq -r '.todos[] | select(.id == "D") | .order_index' "$LIST")"

report
