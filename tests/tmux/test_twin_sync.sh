#!/bin/bash

# owed items live twice (project list + daily twin); a tmux-side change to one
# side must reach the other the same way mcp/server.js syncTwin does.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_harness.sh"

SCRIPTS="$SCRIPT_DIR/../../tmux/scripts"
export DOIT_DATA_DIR="$TEST_TMPDIR/data"
source "$SCRIPTS/get-active-list.sh"
source "$SCRIPTS/lib-twin.sh"
PROJ="$LISTS_DIR/proj.json"
DAILY="$LISTS_DIR/daily.json"

reset_fixture() {
    mkdir -p "$LISTS_DIR"
    cat > "$PROJ" <<'JSON'
{"todos":[
  {"id":"P1","text":"owed in daily #1: merge it","done":false,"in_progress":false,"order_index":1,"twin":{"list":"daily","id":"D1"}},
  {"id":"P2","text":"plain","done":false,"in_progress":false,"order_index":2}
],"_metadata":{}}
JSON
    cat > "$DAILY" <<'JSON'
{"todos":[
  {"id":"D1","text":"proj: merge it","done":false,"in_progress":true,"order_index":1,"twin":{"list":"proj","id":"P1"}}
],"_metadata":{"deleted_todos":[{"id":"OLD","text":"old"}]}}
JSON
}
field() { jq -c --arg id "$2" ".todos[] | select(.id == \$id) | $3" "$1"; }

describe "twin_ref"

reset_fixture
it "returns list and id of the twin"
assert_eq "daily	D1" "$(twin_ref "$PROJ" P1)"
it "is empty for an item without a twin"
assert_eq "" "$(twin_ref "$PROJ" P2)"

describe "twin_apply"

reset_fixture
it "complete prints a status line"
assert_eq 'twin in "daily": complete' "$(twin_apply "$(twin_ref "$PROJ" P1)" complete 1700000000)"
it "complete sets done, clears in_progress, copies completed_at"
assert_eq '[true,false,1700000000]' "$(field "$DAILY" D1 '[.done, .in_progress, .completed_at]')"
it "complete bumps the twin list updated_at"
assert_not_empty "$(jq -r '._metadata.updated_at // empty' "$DAILY")"

twin_apply "daily	D1" complete "" >/dev/null
it "complete without a source stamp falls back to now"
assert_eq "true" "$(field "$DAILY" D1 '.completed_at > 1700000000')"

twin_apply "daily	D1" revert >/dev/null
it "revert clears done and completed_at"
assert_eq '[false,false,null]' "$(field "$DAILY" D1 '[.done, .in_progress, .completed_at]')"

twin_apply "daily	D1" priority urgent >/dev/null
it "priority copies the value"
assert_eq '"urgent"' "$(field "$DAILY" D1 '.priorities')"
twin_apply "daily	D1" priority "" >/dev/null
it "priority empty deletes the field"
assert_eq 'false' "$(field "$DAILY" D1 'has("priorities")')"

twin_apply "daily	D1" due 2026-11-01 >/dev/null
it "due copies the date"
assert_eq '"2026-11-01"' "$(field "$DAILY" D1 '.due_date')"
twin_apply "daily	D1" due "" >/dev/null
it "due empty deletes the field"
assert_eq 'false' "$(field "$DAILY" D1 'has("due_date")')"

twin_apply "daily	D1" delete >/dev/null
it "delete removes the twin from todos"
assert_eq '0' "$(jq '[.todos[] | select(.id == "D1")] | length' "$DAILY")"
it "delete puts the twin first in deleted_todos"
assert_eq '"D1"' "$(jq -c '._metadata.deleted_todos[0].id' "$DAILY")"

it "restore prints a status line"
assert_eq 'twin in "daily": restore' "$(twin_apply "daily	D1" restore)"
it "restore puts the twin back in todos with its twin ref"
assert_eq '{"list":"proj","id":"P1"}' "$(field "$DAILY" D1 '.twin')"
it "restore drops it from deleted_todos and keeps the rest"
assert_eq '["OLD"]' "$(jq -c '[._metadata.deleted_todos[].id]' "$DAILY")"

jq '(.todos[] | select(.id == "D1")).description = "from: proj #1 (id P1)\n\nwhy"' "$DAILY" > "$DAILY.tmp" && mv "$DAILY.tmp" "$DAILY"
twin_apply "daily	D1" relink other >/dev/null
it "relink points the twin at the new list"
assert_eq '{"list":"other","id":"P1"}' "$(field "$DAILY" D1 '.twin')"
it "relink renames the twin's list label and from: line"
assert_eq '"other: merge it"' "$(field "$DAILY" D1 '.text')"
assert_eq '"from: other #1 (id P1)\n\nwhy"' "$(field "$DAILY" D1 '.description')"
twin_apply "daily	D1" relink proj >/dev/null
it "relink back restores the label"
assert_eq '"proj: merge it"' "$(field "$DAILY" D1 '.text')"

it "restore of an id not in deleted_todos is a no-op with a message"
assert_eq 'twin D1 no longer in "daily"' "$(twin_apply "daily	D1" restore)"

it "the reverse direction (daily -> project) works the same"
twin_apply "$(twin_ref "$DAILY" D1)" complete 42 >/dev/null
assert_eq '[true,42]' "$(field "$PROJ" P1 '[.done, .completed_at]')"

describe "twin_apply: missing twin"

reset_fixture
before=$(cat "$DAILY")
it "twin id missing: message, no file change"
assert_eq 'twin GONE no longer in "daily"' "$(twin_apply "daily	GONE" complete 1)"
assert_eq "$before" "$(cat "$DAILY")" "daily.json changed"
it "twin list missing: message"
assert_eq 'twin list "nope" is gone' "$(twin_apply "nope	X" complete 1)"
it "no twin: no output"
assert_eq "" "$(twin_apply "$(twin_ref "$PROJ" P2)" complete 1)"
it "unknown op fails"
twin_apply "daily	D1" bogus >/dev/null
assert_eq "1" "$?"

describe "todo-interactive.sh update_todo"

# the script runs an fzf loop on load, so pull just the function out of it
eval "$(sed -n '/^update_todo() {/,/^}/p' "$SCRIPTS/todo-interactive.sh")"
TODO_LIST_PATH="$PROJ"

reset_fixture
update_todo P1 complete
it "complete syncs the twin with the same completed_at"
assert_eq "$(field "$PROJ" P1 '.completed_at')" "$(field "$DAILY" D1 '.completed_at')"
it "complete sets TWIN_MSG"
assert_eq 'twin in "daily": complete' "$TWIN_MSG"

update_todo P1 revert
it "revert syncs the twin"
assert_eq '[false,null]' "$(field "$DAILY" D1 '[.done, .completed_at]')"

update_todo P1 toggle
it "toggle pending -> in_progress leaves the twin alone"
assert_eq "" "$TWIN_MSG"
update_todo P1 toggle
it "toggle in_progress -> done completes the twin"
assert_eq 'true' "$(field "$DAILY" D1 '.done')"
update_todo P1 toggle
it "toggle done -> pending reverts the twin"
assert_eq 'false' "$(field "$DAILY" D1 '.done')"

update_todo P1 start
it "start does not sync"
assert_eq "" "$TWIN_MSG"

update_todo P1 priority critical
it "priority syncs"
assert_eq '"critical"' "$(field "$DAILY" D1 '.priorities')"
update_todo P1 priority default
it "priority default clears the twin"
assert_eq 'false' "$(field "$DAILY" D1 'has("priorities")')"

update_todo P2 complete
it "an item without a twin leaves daily untouched"
assert_eq "" "$TWIN_MSG"

describe "todo-toggle.sh"

FAKE_BIN="$TEST_TMPDIR/bin"
mkdir -p "$FAKE_BIN"
printf '#!/bin/bash\n[[ "$1" == display-message ]] && echo "$2" >> "%s/msgs"\n' "$TEST_TMPDIR" > "$FAKE_BIN/tmux"
chmod +x "$FAKE_BIN/tmux"
run_toggle() {
    env -u TMUX -u DOIT_PINNED_LIST PATH="$FAKE_BIN:$PATH" DOIT_ACTIVE_LIST=proj \
        bash "$SCRIPTS/todo-toggle.sh"
}

reset_fixture
run_toggle
it "toggle to done stamps completed_at"
assert_eq 'true' "$(field "$PROJ" P1 '.done and (.completed_at | type == "number")')"
it "toggle to done completes the twin with the same stamp"
assert_eq "$(field "$PROJ" P1 '.completed_at')" "$(field "$DAILY" D1 '.completed_at')"
it "toggle message names the twin"
assert_contains "$(tail -1 "$TEST_TMPDIR/msgs")" 'twin in "daily": complete'

jq '(.todos[] | select(.id == "P1")).in_progress = true' "$PROJ" > "$PROJ.tmp" && mv "$PROJ.tmp" "$PROJ"
run_toggle
it "toggle back to pending clears completed_at"
assert_eq '[false,null]' "$(field "$PROJ" P1 '[.done, .completed_at]')"
it "toggle back to pending reverts the twin"
assert_eq '[false,null]' "$(field "$DAILY" D1 '[.done, .completed_at]')"

describe "todo-interactive.sh main loop: d / u / h"

# fake fzf answers each call with the next file in $FZF_SCRIPT, then quits the loop
FZF_SCRIPT="$TEST_TMPDIR/fzf"
mkdir -p "$FZF_SCRIPT"
cat > "$FAKE_BIN/fzf" << SH
#!/bin/bash
cat > /dev/null
n=\$(( \$(cat "$FZF_SCRIPT/n" 2>/dev/null || echo 0) + 1 ))
echo "\$n" > "$FZF_SCRIPT/n"
[[ -f "$FZF_SCRIPT/\$n" ]] || exit 130
cat "$FZF_SCRIPT/\$n"
SH
chmod +x "$FAKE_BIN/fzf"
run_loop() {
    rm -f "$FZF_SCRIPT"/*
    local i=0 r
    for r in "$@"; do i=$((i + 1)); printf '%b\n' "$r" > "$FZF_SCRIPT/$i"; done
    # the y lands after the loop's tty flush, so the delete prompt gets it
    (sleep 1; printf y) | env -u TMUX -u DOIT_PINNED_LIST -u DOIT_ACTIVE_LIST PATH="$FAKE_BIN:$PATH" \
        bash "$SCRIPTS/todo-interactive.sh" --list proj > "$TEST_TMPDIR/loop.out" 2>&1
}

reset_fixture
run_loop 'd\nmerge it [P1]'
it "d deletes the twin too"
assert_eq '["D1","OLD"]' "$(jq -c '[._metadata.deleted_todos[].id]' "$DAILY")"
assert_eq '0' "$(jq '[.todos[] | select(.id == "D1")] | length' "$DAILY")"
it "d status line names the twin"
assert_contains "$(cat "$TEST_TMPDIR/loop.out")" 'twin in "daily": delete'

reset_fixture
run_loop 'd\nmerge it [P1]' 'u\nplain [P2]'
it "u after d restores the item and its twin"
assert_eq '1 1' "$(jq '[.todos[] | select(.id == "P1")] | length' "$PROJ") $(jq '[.todos[] | select(.id == "D1")] | length' "$DAILY")"
assert_eq '["OLD"]' "$(jq -c '[._metadata.deleted_todos[].id]' "$DAILY")"

reset_fixture
run_loop 'h\nmerge it [P1]' '2026-12-01'
it "h sets the twin due date"
assert_eq '"2026-12-01"' "$(field "$DAILY" D1 '.due_date')"
run_loop 'h\nmerge it [P1]' ''
it "h with empty input clears the twin due date"
assert_eq 'false' "$(field "$DAILY" D1 'has("due_date")')"

reset_fixture
run_loop 'x\nmerge it [P1]' 'u\nmerge it [P1]'
it "u after x reverts the twin"
assert_eq '[false,null]' "$(field "$DAILY" D1 '[.done, .completed_at]')"
assert_contains "$(cat "$TEST_TMPDIR/loop.out")" 'twin in "daily": revert'

reset_fixture
run_loop 'x\nmerge it [P1]' 'X\nmerge it [P1]' 'u\nmerge it [P1]'
it "u after X brings back the done stamp, and the twin gets the same one"
assert_eq '[true,"number",true]' "$(jq -c --slurpfile d "$DAILY" \
    '.todos[] | select(.id == "P1") | [.done, (.completed_at | type), (.completed_at == ($d[0].todos[] | select(.id == "D1") | .completed_at))]' "$PROJ")"

reset_fixture
echo '{"todos":[],"_metadata":{}}' > "$LISTS_DIR/other.json"
run_loop 'm\nmerge it [P1]' 'other'
it "m moves the item and relinks its twin"
assert_eq '1 {"list":"other","id":"P1"}' "$(jq '.todos | length' "$LISTS_DIR/other.json") $(field "$DAILY" D1 '.twin')"
assert_contains "$(cat "$TEST_TMPDIR/loop.out")" 'twin in "daily": relink'

describe "todo-list-manager.sh rename_list"

eval "$(sed -n '/^rename_list() {/,/^}/p' "$SCRIPTS/todo-list-manager.sh")"
CURRENT_LIST=daily

reset_fixture
rename_list proj <<< "proj2" > /dev/null
it "rename relinks twins in other lists"
assert_eq '{"list":"proj2","id":"P1"}' "$(field "$DAILY" D1 '.twin')"

reset_fixture
jq '.todos += [{"id":"P3","text":"a","done":false,"twin":{"list":"proj","id":"P4"}},
               {"id":"P4","text":"b","done":false,"twin":{"list":"proj","id":"P3"}}]' "$PROJ" > "$PROJ.tmp" && mv "$PROJ.tmp" "$PROJ"
rename_list proj <<< "proj3" > /dev/null
it "rename relinks a pair that lives inside the renamed list"
assert_eq '["proj3","proj3"]' "$(jq -c '[.todos[] | select(.id == "P3" or .id == "P4") | .twin.list]' "$LISTS_DIR/proj3.json")"

describe "todo-list-manager.sh: daily is permanent"

eval "$(sed -n '/^delete_list() {/,/^}/p' "$SCRIPTS/todo-list-manager.sh")"
CURRENT_LIST=proj
it "rename refuses daily"
assert_contains "$(rename_list daily <<< "inbox")" "daily is permanent"
it "delete refuses daily"
assert_contains "$(delete_list daily <<< "yes")" "daily is permanent"
assert_eq "yes" "$([[ -f "$DAILY" ]] && echo yes)" "daily.json is gone"

report
