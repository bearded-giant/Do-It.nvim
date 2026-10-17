#!/bin/bash

# daily is the owed inbox: its done section shows only items completed today,
# so yesterday's checked-off twins stop piling up. Older items stay on disk.
# Every other list keeps showing all its done items.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_harness.sh"

SCRIPTS="$SCRIPT_DIR/../../tmux/scripts"
DATA="$TEST_TMPDIR/data"
mkdir -p "$DATA/lists"

NOW=$(date +%s)
YESTERDAY=$(( NOW - 86400 - 3600 ))
for name in daily proj; do
    cat > "$DATA/lists/$name.json" <<JSON
{
  "todos": [
    {"id":"P","text":"still open","done":false,"in_progress":false,"order_index":1},
    {"id":"T","text":"done today","done":true,"in_progress":false,"order_index":2,"completed_at":$NOW},
    {"id":"Y","text":"done yesterday","done":true,"in_progress":false,"order_index":3,"completed_at":$YESTERDAY},
    {"id":"N","text":"done no stamp","done":true,"in_progress":false,"order_index":4}
  ],
  "_metadata": {"name":"$name"}
}
JSON
done

run_script() {
    echo "{\"active_list\":\"$1\"}" > "$DATA/session.json"
    env -u TMUX DOIT_DATA_DIR="$DATA" bash "$SCRIPTS/$2" ${3:+"$3"} 2>/dev/null </dev/null \
        | sed 's/\x1b\[[0-9;]*m//g'
}

run_preview() {
    sed -n '/^preview_list() {/,/^}/p' "$SCRIPTS/todo-list-manager.sh" > "$TEST_TMPDIR/fn.sh"
    eval "$(source "$SCRIPTS/lib-origin.sh"; declare -p ORIGIN_JQ RECENT_DONE_JQ)"
    ORIGIN_JQ="$ORIGIN_JQ" RECENT_DONE_JQ="$RECENT_DONE_JQ" \
    LISTS_DIR="$DATA/lists" SHOW_COMPLETED=true FZF_PREVIEW_COLUMNS=120 \
        bash -c "source '$TEST_TMPDIR/fn.sh'; export -f preview_list; bash -c 'preview_list $1'" 2>&1
}

describe "todo-interactive.sh --format: done section"

OUT=$(run_script daily todo-interactive.sh --format)
it "daily shows today's done item"
assert_contains "$OUT" "done today"
it "daily hides yesterday's done item"
assert_eq "0" "$(grep -c 'done yesterday' <<< "$OUT")"
it "daily hides a done item with no completed_at"
assert_eq "0" "$(grep -c 'done no stamp' <<< "$OUT")"
it "daily still shows pending items"
assert_contains "$OUT" "still open"

OUT=$(run_script proj todo-interactive.sh --format)
it "a project list still shows yesterday's done item"
assert_contains "$OUT" "done yesterday"
it "a project list still shows a done item with no completed_at"
assert_contains "$OUT" "done no stamp"

describe "todo-popup.sh: completed block"

OUT=$(run_script daily todo-popup.sh)
it "daily shows today's done item"
assert_contains "$OUT" "done today"
it "daily hides yesterday's done item"
assert_eq "0" "$(grep -c 'done yesterday' <<< "$OUT")"

OUT=$(run_script daily todo-popup.sh)
it "daily stats count only today's done item"
assert_contains "$OUT" "Stats: Total: 2 | Done: 1 | In Progress: 0 | Pending: 1"

OUT=$(run_script proj todo-popup.sh)
it "a project list still shows yesterday's done item"
assert_contains "$OUT" "done yesterday"
it "a project list stats count every done item"
assert_contains "$OUT" "Stats: Total: 4 | Done: 3 | In Progress: 0 | Pending: 1"

describe "todo-interactive.sh header"

header_done() {
    sed -n '/^while true; do/,/LIST=\$(format_todos)/p' "$SCRIPTS/todo-interactive.sh" \
        | grep 'done_count=' > "$TEST_TMPDIR/hdr.sh"
    eval "$(source "$SCRIPTS/lib-origin.sh"; declare -p RECENT_DONE_JQ)"
    ACTIVE_LIST_NAME="$1" TODO_LIST_PATH="$DATA/lists/$1.json" RECENT_DONE_JQ="$RECENT_DONE_JQ" \
        bash -c "source '$TEST_TMPDIR/hdr.sh'; echo \$done_count"
}
it "daily header counts only today's done item"
assert_eq "1" "$(header_done daily)"
it "a project list header counts every done item"
assert_eq "3" "$(header_done proj)"

describe "todo-list-manager.sh preview"

OUT=$(run_preview daily)
it "runs with no jq or command errors"
assert_eq "0" "$(grep -cE 'command not found|jq: error' <<< "$OUT")"
it "daily shows today's done item"
assert_contains "$OUT" "done today"
it "daily hides yesterday's done item"
assert_eq "0" "$(grep -c 'done yesterday' <<< "$OUT")"
it "daily stats count only today's done item"
assert_contains "$OUT" "Total: 2  Pending: 1  In Progress: 0  Done: 1"

OUT=$(run_preview proj)
it "a project list stats count every done item"
assert_contains "$OUT" "Total: 4  Pending: 1  In Progress: 0  Done: 3"
it "a project list still shows yesterday's done item"
assert_contains "$OUT" "done yesterday"

report
