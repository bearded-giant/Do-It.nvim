#!/bin/bash

# tests for the overdue count the list views badge lists with

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_harness.sh"

SCRIPTS="$SCRIPT_DIR/../../tmux/scripts"
TODAY=$(date +%F)
PAST=$(date -v-3d +%F 2>/dev/null || date -d '3 days ago' +%F)
FUTURE=$(date -v+3d +%F 2>/dev/null || date -d '3 days' +%F)

export DOIT_DATA_DIR="$TEST_TMPDIR/data"
mkdir -p "$DOIT_DATA_DIR/lists"

cat > "$DOIT_DATA_DIR/lists/daily.json" <<JSON
{"todos":[
 {"id":"1","text":"late one","done":false,"due_date":"$PAST"},
 {"id":"2","text":"late two","done":false,"due_date":"$PAST"},
 {"id":"3","text":"due today","done":false,"due_date":"$TODAY"},
 {"id":"4","text":"later","done":false,"due_date":"$FUTURE"},
 {"id":"5","text":"finished late","done":true,"due_date":"$PAST"},
 {"id":"6","text":"no due date","done":false}
]}
JSON

cat > "$DOIT_DATA_DIR/lists/clean.json" <<JSON
{"todos":[{"id":"1","text":"nothing due","done":false}]}
JSON

source "$SCRIPTS/get-active-list.sh"

describe "overdue_count_for_list"

it "counts only open items past their due date"
assert_eq "2" "$(overdue_count_for_list daily)"

it "is zero for a list with nothing overdue"
assert_eq "0" "$(overdue_count_for_list clean)"

it "is zero for a missing list"
assert_eq "0" "$(overdue_count_for_list nope)"

describe "list view rows"

for script in todo-list-manager.sh todo-list-switch.sh; do
    ROWS=$(cd "$TEST_TMPDIR" && DOIT_ACTIVE_LIST=daily bash -c "
        source '$SCRIPTS/get-active-list.sh'
        COLOR_DIM=''; COLOR_RED=''; COLOR_RESET=''
        CURRENT_LIST=daily
        LIVE_SESSIONS=''
        $(sed -n '/^overdue_badge_for_list() {/,/^}/p' "$SCRIPTS/$script")
        $(sed -n '/^badge_for_list() {/,/^}/p' "$SCRIPTS/$script")
        $(sed -n '/^build_rows() {/,/^}/p' "$SCRIPTS/$script")
        build_rows")

    it "$script badges the overdue count"
    assert_contains "$ROWS" "!2 overdue"

    it "$script leaves clean lists unbadged"
    assert_eq "0" "$(grep 'clean' <<< "$ROWS" | grep -c overdue)"

    it "$script keeps the list name as the first field"
    assert_eq "daily" "$(grep daily <<< "$ROWS" | sed 's/^[* ]*//' | awk '{print $1}')"
done

report
