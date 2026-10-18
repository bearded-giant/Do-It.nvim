#!/bin/bash

# status-bar chip text: "<session>:<window>: <todo>" with the label whole
# unless @doit-list-chars caps it, todo cut at @doit-todo-chars (default 25)
# without its claude: marker and with "owed in <list> #N:" shortened to
# "owed:", "<session>:<window>: no active" when idle.
# Outside tmux the list name is the label. A real tmux server on a private
# socket plays the user's; the outside-tmux case gets a no-op tmux on PATH.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_harness.sh"

SCRIPTS="$SCRIPT_DIR/../../tmux/scripts"
DATA="$TEST_TMPDIR/data"
mkdir -p "$DATA/lists"
export DOIT_DATA_DIR="$DATA"

SOCK="$TEST_TMPDIR/tmux.sock"
trap 'tmux -S "$SOCK" kill-server 2>/dev/null; rm -rf "$TEST_TMPDIR"' EXIT
T() { tmux -S "$SOCK" "$@"; }
T -f /dev/null new-session -d -s s -n short -x 80 -y 24
for w in a-very-long-window-name marked 'tmux config' nobody owing; do T new-window -d -t s: -n "$w"; done
TM="$SOCK,$(T display -p '#{pid}'),0"

NOOP_BIN="$TEST_TMPDIR/bin"
mkdir -p "$NOOP_BIN"
printf '#!/bin/sh\nexit 0\n' > "$NOOP_BIN/tmux"
chmod +x "$NOOP_BIN/tmux"

mklist() {
    jq -n --arg text "$2" --argjson active "${3:-false}" \
        '{todos: (if $text == "" then [] else [{id: "t1", text: $text, done: false, in_progress: $active, order_index: 0}] end), _metadata: {}}' \
        > "$DATA/lists/$1.json"
}

# chip for window $1 the way the status bar asks for it (#{window_id})
chip() {
    local wid
    wid=$(T display -p -t "$1" '#{window_id}')
    env -u TMUX_PANE -u DOIT_ACTIVE_LIST -u DOIT_PINNED_LIST -u DOIT_WINDOW TMUX="$TM" \
        bash "$SCRIPTS/todo-exec.sh" "$wid"
}

with_opt() {
    local name="$1" val="$2"; shift 2
    T set -g "$name" "$val"
    "$@"
    T set -gu "$name"
}

mklist daily ""
mklist hello-test "ship the thing" true
mklist recharge-auth-complete-auth-service "long list item" true
mklist marked "claude: [decision] 12. pick the status bar layout (dep on #3)" true
mklist owing "[gate] 27. owed in daily #129: prod registry cutover" true
cat > "$DATA/session.json" << 'JSON'
{"active_list": "daily", "sessions": {"s:short": "hello-test", "s:a-very-long-window-name": "recharge-auth-complete-auth-service", "s:marked": "marked", "s:owing": "owing"}}
JSON

describe "status chip text"

it "unlinked window: daily, idle"
assert_eq "s:nobody: no active" "$(chip s:nobody)"

it "window key labels the todo, not the list name"
assert_eq "s:short: ship the thing" "$(chip s:short)"

it "long window key shown whole by default"
assert_eq "s:a-very-long-window-name: long list item" "$(chip s:a-very-long-window-name)"

it "@doit-list-chars caps the label"
assert_eq "s:a-very-l...: long list item" "$(with_opt @doit-list-chars 10 chip s:a-very-long-window-name)"

it "claude: marker dropped, todo cut at 25 chars by default"
assert_eq "s:marked: [decision] 12. pick the s..." "$(chip s:marked)"

it "@doit-todo-chars widens the todo text"
assert_eq "s:marked: [decision] 12. pick the status bar layout (dep on #3)" "$(with_opt @doit-todo-chars 80 chip s:marked)"

it "owed twin label collapses so the task stays in view"
assert_eq "s:owing: [gate] 27. owed: prod registry cutover" "$(with_opt @doit-todo-chars 80 chip s:owing)"

it "window name with spaces labels the chip whole"
assert_eq "s:tmux config: no active" "$(chip 's:tmux config')"

it "the label follows a renamed window, and so does its list"
T rename-window -t s:short renamed
assert_eq "s:renamed: ship the thing" "$(chip s:renamed)"

it "by hand, a session:window name works as the argument"
assert_eq "s:marked: [decision] 12. pick the s..." "$(env -u TMUX_PANE TMUX="$TM" bash "$SCRIPTS/todo-exec.sh" 's:marked')"

it "outside tmux with no window: list name labels the chip"
assert_eq "daily: no active" "$(env -u TMUX -u TMUX_PANE -u DOIT_WINDOW PATH="$NOOP_BIN:$PATH" bash "$SCRIPTS/todo-exec.sh")"

report
