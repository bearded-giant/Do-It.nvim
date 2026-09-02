#!/bin/bash

# tests for nested todos in the tmux UI: todo-interactive.sh --format renders a
# subtree contiguous and indented inside its ROOT's section, and todo-move.sh
# only swaps order_index with a sibling so a subtree moves as one.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_harness.sh"

SCRIPTS="$SCRIPT_DIR/../../tmux/scripts"
DATA="$TEST_TMPDIR/data"
mkdir -p "$DATA/lists"
echo '{"active_list":"nest"}' > "$DATA/session.json"
LIST="$DATA/lists/nest.json"

cat > "$LIST" <<'EOF'
{
  "todos": [
    {"id":"A","text":"root a","done":false,"in_progress":false,"order_index":1},
    {"id":"A1","text":"child a1","done":false,"in_progress":false,"order_index":2,"parent_id":"A"},
    {"id":"A2","text":"done child a2","done":true,"in_progress":false,"order_index":3,"parent_id":"A","completed_at":50},
    {"id":"B","text":"root b","done":false,"in_progress":false,"order_index":4},
    {"id":"I","text":"running root","done":false,"in_progress":true,"order_index":5},
    {"id":"I1","text":"pending child of running","done":false,"in_progress":false,"order_index":6,"parent_id":"I"},
    {"id":"Z","text":"finished root","done":true,"in_progress":false,"order_index":7,"completed_at":100},
    {"id":"Z1","text":"pending child of finished","done":false,"in_progress":false,"order_index":8,"parent_id":"Z"},
    {"id":"U","text":"urgent root","done":false,"in_progress":false,"order_index":9,"priorities":"urgent"},
    {"id":"U1","text":"default child of urgent","done":false,"in_progress":false,"order_index":10,"parent_id":"U"}
  ],
  "_metadata": {"name":"nest"}
}
EOF

# fzf transform binds run outside tmux; TMUX is dropped so a project-list option
# on the developer's server cannot redirect the fixture list
run_format() {
    env -u TMUX DOIT_DATA_DIR="$DATA" bash "$SCRIPTS/todo-interactive.sh" --format 2>/dev/null \
        | sed 's/\x1b\[[0-9;]*m//g'
}

# the row for an id, with trailing padding removed
row_for() {
    grep -F "[$1]" <<< "$FORMAT" | head -1 | sed 's/ *\[[^]]*\]$//'
}

# 1-based line of the row carrying an id
line_of() {
    grep -nF "[$1]" <<< "$FORMAT" | head -1 | cut -d: -f1
}

describe "todo-interactive.sh --format: nested rows"

FORMAT=$(run_format)

it "renders every todo exactly once"
for id in A A1 A2 B I I1 Z Z1 U U1; do
    assert_eq "1" "$(grep -cF "[$id]" <<< "$FORMAT")" "id $id rendered $(grep -cF "[$id]" <<< "$FORMAT") times"
done

it "indents a child two spaces under its parent"
assert_eq "  " "$(row_for A1 | cut -c1-2)"

it "keeps a child directly below its parent"
assert_eq "$(( $(line_of A) + 1 ))" "$(line_of A1)"

it "keeps a done subtask under its open parent instead of in the completed block"
assert_eq "$(( $(line_of A1) + 1 ))" "$(line_of A2)"

it "marks the done subtask with the done glyph"
assert_contains "$(row_for A2)" "✓"

it "puts the done subtask above the completed divider"
DIVIDER_LINE=$(grep -n '^─' <<< "$FORMAT" | head -1 | cut -d: -f1)
TESTS_RUN=$((TESTS_RUN + 1))
if [[ "$(line_of A2)" -lt "$DIVIDER_LINE" ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1)); echo "  pass: $CURRENT_TEST"
else
    TESTS_FAILED=$((TESTS_FAILED + 1)); echo "  FAIL: $CURRENT_TEST"
    FAILURES="${FAILURES}\n  - $CURRENT_TEST"
fi

it "keeps a pending child inside the in-progress section with its running parent"
assert_eq "$(( $(line_of I) + 1 ))" "$(line_of I1)"

it "keeps a pending child of a completed parent below the divider with it"
assert_eq "$(( $(line_of Z) + 1 ))" "$(line_of Z1)"

it "keeps a default-priority child inside its urgent parent's group"
assert_eq "$(( $(line_of U) + 1 ))" "$(line_of U1)"

it "does not emit a Default header between the urgent parent and its child"
BETWEEN=$(sed -n "$(line_of U),$(line_of U1)p" <<< "$FORMAT" | grep -cx 'Default')
assert_eq "0" "$BETWEEN"

it "puts the urgent subtree before the default roots"
TESTS_RUN=$((TESTS_RUN + 1))
if [[ "$(line_of U1)" -lt "$(line_of A)" ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1)); echo "  pass: $CURRENT_TEST"
else
    TESTS_FAILED=$((TESTS_FAILED + 1)); echo "  FAIL: $CURRENT_TEST"
    FAILURES="${FAILURES}\n  - $CURRENT_TEST"
fi

describe "todo-move.sh: subtree-aware reorder"

order_of() {
    jq -r --arg id "$1" '.todos[] | select(.id == $id) | .order_index' "$LIST"
}

it "moving a root up swaps with the previous root, not with that root's child"
env -u TMUX DOIT_DATA_DIR="$DATA" bash "$SCRIPTS/todo-move.sh" up "root b [B]" > /dev/null 2>&1
assert_eq "1" "$(order_of B)"
it "the previous root took the moved root's slot"
assert_eq "4" "$(order_of A)"
it "the previous root's child kept its own order_index"
assert_eq "2" "$(order_of A1)"

it "the moved root renders above the other root with that root's subtree intact"
FORMAT=$(run_format)
TESTS_RUN=$((TESTS_RUN + 1))
if [[ "$(line_of B)" -lt "$(line_of A)" && "$(line_of A1)" -eq "$(( $(line_of A) + 1 ))" ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1)); echo "  pass: $CURRENT_TEST"
else
    TESTS_FAILED=$((TESTS_FAILED + 1)); echo "  FAIL: $CURRENT_TEST"
    FAILURES="${FAILURES}\n  - $CURRENT_TEST"
fi

it "a child with no open sibling stays put"
env -u TMUX DOIT_DATA_DIR="$DATA" bash "$SCRIPTS/todo-move.sh" up "  child a1 [A1]" > /dev/null 2>&1
assert_eq "2" "$(order_of A1)"

report
