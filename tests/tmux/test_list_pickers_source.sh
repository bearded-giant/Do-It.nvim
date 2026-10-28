#!/bin/bash

# tests for the source filter, create stamp, and rename in the tmux list pickers

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_harness.sh"

SCRIPTS="$SCRIPT_DIR/../../tmux/scripts"
export DOIT_DATA_DIR="$TEST_TMPDIR/data"
mkdir -p "$DOIT_DATA_DIR/lists"
source "$SCRIPTS/get-active-list.sh"
source "$SCRIPTS/lib-source.sh"
source "$SCRIPTS/lib-twin.sh"

COLOR_RED="" COLOR_YELLOW="" COLOR_DIM_YELLOW="" COLOR_GREEN="" COLOR_RESET=""
LIVE_WINDOWS=""
sleep() { :; }

echo '{"todos":[],"_metadata":{}}' > "$LISTS_DIR/daily.json"
echo '{"todos":[],"_metadata":{"source":"user"}}' > "$LISTS_DIR/mine.json"
echo '{"todos":[],"_metadata":{}}' > "$LISTS_DIR/bot.json"
echo '{"todos":[],"_metadata":{"source":"mcp"}}' > "$LISTS_DIR/bot2.json"
echo '{"active_list":"daily"}' > "$SESSION_FILE"

names() { build_rows | sed 's/^[* ]*//' | awk '{print $1}' | tr '\n' ' '; }

for script in todo-list-manager.sh todo-list-switch.sh; do
    eval "$(sed -n '/^overdue_badge_for_list() {/,/^}/p; /^badge_for_list() {/,/^}/p; /^build_rows() {/,/^}/p' "$SCRIPTS/$script")"

    describe "$script rows"
    CURRENT_LIST=daily

    it "all shows every list"
    _update_session_file '.source_filter = "all"'
    assert_eq "daily bot bot2 mine " "$(names)"

    it "mine shows daily and user lists"
    _update_session_file '.source_filter = "mine"'
    assert_eq "daily mine " "$(names)"

    it "claude hides daily and user lists"
    _update_session_file '.source_filter = "claude"'
    CURRENT_LIST=bot
    assert_eq "bot bot2 " "$(names)"

    it "claude keeps the active list when it is filtered out"
    CURRENT_LIST=daily
    assert_eq "daily bot bot2 " "$(names)"
    CURRENT_LIST=mine
    assert_eq "bot bot2 mine " "$(names | tr ' ' '\n' | sort | tr '\n' ' ')"

    it "mine keeps an active claude list"
    _update_session_file '.source_filter = "mine"'
    CURRENT_LIST=bot
    assert_eq "bot daily mine " "$(names | tr ' ' '\n' | sort | tr '\n' ' ')"

    it "rows tag daily and user lists mine, claude lists stay bare"
    _update_session_file '.source_filter = "all"'
    CURRENT_LIST=bot
    rows=$(build_rows | sed 's/\x1b\[[0-9;]*m//g')
    assert_eq "1" "$(grep -cE '^ *daily \([0-9]+ pending\) mine' <<< "$rows")"
    assert_eq "1" "$(grep -cE '^ *mine mine$' <<< "$rows")"
    assert_eq "0" "$(grep -cE 'bot2? mine' <<< "$rows")"
done

describe "create_list"

eval "$(sed -n '/^create_list() {/,/^rename_list() {/p' "$SCRIPTS/todo-list-manager.sh" | sed '$d')"
CURRENT_LIST=daily
printf 'fresh one\nn\n' | create_list > /dev/null
it "create stamps source user and keeps timestamps"
assert_eq "user true" "$(jq -r '[._metadata.source, (._metadata.created_at | type == "number")] | join(" ")' "$LISTS_DIR/$(sanitize_list_name 'fresh one').json")"

describe "rename_list"

eval "$(sed -n '/^rename_list() {/,/^}/p' "$SCRIPTS/todo-list-manager.sh")"
echo '{"todos":[{"id":"1","text":"x","done":false}],"_metadata":{"source":"user","created_at":7}}' > "$LISTS_DIR/old.json"
rename_list old <<< "renamed" > /dev/null
it "rename keeps source and other metadata"
assert_eq "user 7" "$(jq -r '"\(._metadata.source) \(._metadata.created_at)"' "$LISTS_DIR/renamed.json")"

report
