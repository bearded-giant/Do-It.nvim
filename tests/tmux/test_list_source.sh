#!/bin/bash

# tests for lib-source.sh: per-list source flag and the shared view filter

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_harness.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
export DOIT_DATA_DIR="$TEST_TMPDIR/data"
mkdir -p "$DOIT_DATA_DIR/lists"
source "$REPO_ROOT/tmux/scripts/get-active-list.sh"
source "$REPO_ROOT/tmux/scripts/lib-source.sh"

echo '{"todos":[],"_metadata":{"created_at":1}}' > "$LISTS_DIR/unflagged.json"
echo '{"todos":[],"_metadata":{"source":"user"}}' > "$LISTS_DIR/mine.json"
echo '{"todos":[{"id":"t1","text":"keep me","done":false}],"_metadata":{"created_at":5}}' > "$LISTS_DIR/flip.json"
echo '{"todos":[],"_metadata":{}}' > "$LISTS_DIR/daily.json"
echo '{"active_list":"daily","sessions":{"s:w":"flip"}}' > "$SESSION_FILE"

describe "list source flag"

it "unflagged list counts as claude"
list_is_mine unflagged && r=mine || r=claude
assert_eq "claude" "$r"

it "source user counts as mine"
list_is_mine mine && r=mine || r=claude
assert_eq "mine" "$r"

it "daily is always mine"
list_is_mine daily && r=mine || r=claude
assert_eq "mine" "$r"

it "toggle flips claude to user and keeps todos and other metadata"
assert_eq "user" "$(toggle_list_source flip)"
assert_eq "user" "$(jq -r '._metadata.source' "$LISTS_DIR/flip.json")"
assert_eq "5" "$(jq -r '._metadata.created_at' "$LISTS_DIR/flip.json")"
assert_eq "keep me" "$(jq -r '.todos[0].text' "$LISTS_DIR/flip.json")"

it "toggle flips user back to mcp"
assert_eq "mcp" "$(toggle_list_source flip)"

it "toggle leaves daily the user's and its file untouched"
assert_eq "user" "$(toggle_list_source daily)"
assert_eq "{}" "$(jq -c '._metadata' "$LISTS_DIR/daily.json")"

it "toggle on a missing list fails"
toggle_list_source nope >/dev/null && r=ok || r=fail
assert_eq "fail" "$r"

describe "source filter"

it "absent filter reads as all"
assert_eq "all" "$(source_filter)"

it "cycle goes all, mine, claude, all and keeps other session keys"
assert_eq "mine" "$(cycle_source_filter)"
assert_eq "claude" "$(cycle_source_filter)"
assert_eq "all" "$(cycle_source_filter)"
assert_eq "flip" "$(jq -r '.sessions["s:w"]' "$SESSION_FILE")"

it "toggle view lands all on mine, then flips mine and claude"
_update_session_file '.source_filter = "all"'
assert_eq "mine" "$(toggle_source_view)"
assert_eq "claude" "$(toggle_source_view)"
assert_eq "mine" "$(toggle_source_view)"
assert_eq "flip" "$(jq -r '.sessions["s:w"]' "$SESSION_FILE")"
_update_session_file 'del(.source_filter)'

it "list_in_filter honours mine and claude"
shows() { list_in_filter "$1" "$2" && echo y || echo n; }
assert_eq "y n y" "$(shows mine mine) $(shows unflagged mine) $(shows daily mine)"
assert_eq "n y n" "$(shows mine claude) $(shows unflagged claude) $(shows daily claude)"
assert_eq "y y" "$(shows mine all) $(shows unflagged all)"

it "jq predicate matches the shell rule"
got=$(for n in daily mine unflagged; do jq -r --arg n "$n" "$DOIT_SOURCE_JQ"' is_mine($n)' "$LISTS_DIR/$n.json"; done | tr '\n' ' ')
assert_eq "true true false " "$got"

report
