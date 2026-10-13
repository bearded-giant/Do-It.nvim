#!/bin/bash

# status-bar chip text: "<list>: <todo>" with the list name cut at
# @doit-list-chars (default 10), todo cut at @doit-todo-chars (default 25)
# without its claude: marker, "<list>: no active" when idle.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_harness.sh"

SCRIPTS="$SCRIPT_DIR/../../tmux/scripts"
DATA="$TEST_TMPDIR/data"
mkdir -p "$DATA/lists"

# fake tmux: only @doit-todo-chars answers, from $FAKE_TODO_CHARS
FAKE_BIN="$TEST_TMPDIR/bin"
mkdir -p "$FAKE_BIN"
cat > "$FAKE_BIN/tmux" << 'SH'
#!/bin/bash
[[ "$*" == *@doit-todo-chars* ]] && echo "$FAKE_TODO_CHARS"
exit 0
SH
chmod +x "$FAKE_BIN/tmux"

mklist() {
    jq -n --arg text "$2" --argjson active "${3:-false}" \
        '{todos: (if $text == "" then [] else [{id: "t1", text: $text, done: false, in_progress: $active, order_index: 0}] end), _metadata: {}}' \
        > "$DATA/lists/$1.json"
}

chip() {
    env -u TMUX -u DOIT_ACTIVE_LIST -u DOIT_PINNED_LIST PATH="$FAKE_BIN:$PATH" \
        DOIT_DATA_DIR="$DATA" FAKE_TODO_CHARS="${TODO_CHARS:-}" bash "$SCRIPTS/todo-exec.sh" "$1"
}

mklist daily ""
mklist hello-test "ship the thing" true
mklist recharge-auth-complete-auth-service "long list item" true
mklist marked "claude: [decision] 12. pick the status bar layout (dep on #3)" true
cat > "$DATA/session.json" << 'JSON'
{"active_list": "daily", "sessions": {"short": "hello-test", "long": "recharge-auth-complete-auth-service", "marked": "marked"}}
JSON

describe "status chip text"

it "unlinked session: daily, idle"
assert_eq "daily: no active" "$(chip nobody)"

it "short list name shown whole before the todo"
assert_eq "hello-test: ship the thing" "$(chip short)"

it "long list name cut at 10 chars with ellipsis"
assert_eq "recharge-a...: long list item" "$(chip long)"

it "claude: marker dropped, todo cut at 25 chars by default"
assert_eq "marked: [decision] 12. pick the s..." "$(chip marked)"

it "@doit-todo-chars widens the todo text"
assert_eq "marked: [decision] 12. pick the status bar layout (dep on #3)" "$(TODO_CHARS=80 chip marked)"

report
