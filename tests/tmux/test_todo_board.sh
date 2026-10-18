#!/bin/bash

# board rows are claude panes (those with @claude_state), each showing its own
# list: @doit-pane-list, else the window link, else daily. A real tmux server
# on a private socket plays the user's.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_harness.sh"

SCRIPTS="$SCRIPT_DIR/../../tmux/scripts"
DATA="$TEST_TMPDIR/data"
mkdir -p "$DATA/lists"
export DOIT_DATA_DIR="$DATA"

SOCK="$TEST_TMPDIR/tmux.sock"
trap 'tmux -S "$SOCK" kill-server 2>/dev/null; rm -rf "$TEST_TMPDIR"' EXIT
T() { tmux -S "$SOCK" "$@"; }
T -f /dev/null new-session -d -s s -n solo -x 80 -y 24
for w in pair plain bare; do T new-window -d -t s: -n "$w"; done
T split-window -d -t s:pair
TM="$SOCK,$(T display -p '#{pid}'),0"

mklist() {
    jq -n --arg text "$2" --argjson active "${3:-false}" --arg prio "${4:-}" \
        '{todos: (if $text == "" then [] else [{id: "t1", text: $text, done: false, in_progress: $active, priorities: (if $prio == "" then null else $prio end)}] end), _metadata: {}}' \
        > "$DATA/lists/$1.json"
}

board() {
    env -u TMUX_PANE TMUX="$TM" COLUMNS="${1:-60}" bash "$SCRIPTS/todo-board.sh" --once |
        LC_ALL=en_US.UTF-8 sed $'s/\e\\[[0-9;]*[mK]//g'
}

pane() { T display -p -t "$1" '#{pane_id}'; }

describe "todo board"

it "no claude panes: says so"
assert_contains "$(board)" "no claude panes"

mklist daily "my own thing" true
mklist solo-list "claude: [bug] 4. fix the redirect" true critical
mklist left-list "left item" true
mklist right-list "idle item" false
mklist win-list "window item" true

T set -pq -t s:solo @claude_state busy
T set -pq -t s:solo @doit-pane-list solo-list
PAIR_A=$(pane s:pair.0)
PAIR_B=$(pane s:pair.1)
T set -pq -t "$PAIR_A" @claude_state ask
T set -pq -t "$PAIR_A" @doit-pane-list left-list
T set -pq -t "$PAIR_B" @claude_state ready
T set -pq -t "$PAIR_B" @doit-pane-list right-list
T set -wq -t s:pair @doit-window-list win-list
T set -pq -t s:bare @claude_state busy
out=$(board)

it "stamped pane shows its list's active item without the claude: marker"
assert_contains "$out" "▸ [bug] 4. fix the redirect"

it "two claude panes in one window keep their own lists"
assert_contains "$out" "pair $PAIR_A"
assert_contains "$(printf '%s\n' "$out" | grep -A2 "pair $PAIR_A")" "left-list"
assert_contains "$(printf '%s\n' "$out" | grep -A2 "pair $PAIR_B")" "right-list"

it "pane list wins over the window link"
assert_eq "0" "$(printf '%s\n' "$out" | grep -c 'win-list')"

it "idle list shows its open count"
assert_contains "$out" "no active · 1 open"

it "unstamped, unlinked pane falls back to daily"
assert_contains "$(printf '%s\n' "$out" | grep -A2 '● bare')" "▸ my own thing"

it "non-claude window is not a row"
assert_eq "0" "$(printf '%s\n' "$out" | grep -c 'plain')"

it "daily footer shows the user's active item"
assert_eq "▸ my own thing" "$(printf '%s\n' "$out" | grep -A1 '^daily$' | tail -1 | sed 's/^ *//')"

T set -pqu -t "$PAIR_A" @doit-pane-list
it "unstamped pane falls back to the window link"
assert_contains "$(board | grep -A2 "pair $PAIR_A")" "win-list"

it "rows are cut to the pane width"
narrow=$(board 20)
assert_contains "$narrow" "▸ [bug] 4. fix t…"
assert_eq "0" "$(printf '%s\n' "$narrow" | jq -R 'select(length > 20)' | wc -l | tr -d ' ')"

report
