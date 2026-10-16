#!/bin/bash

# per-tmux-window active list: resolution chain, link read/write helpers, the
# pinned (--list) view, and links following windows through renames, moves,
# duplicate names, a tmux restart, and the upgrade from per-session links.
# A real tmux server on a private socket stands in for the user's; every call
# that may reach tmux carries TMUX pointing at it, and the server is started
# with DOIT_DATA_DIR set so its hooks write the fixture, never real data.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_harness.sh"

SCRIPTS="$SCRIPT_DIR/../../tmux/scripts"
DATA="$TEST_TMPDIR/data"
mkdir -p "$DATA/lists"
export DOIT_DATA_DIR="$DATA"

SOCK="$TEST_TMPDIR/tmux.sock"
trap 'tmux -S "$SOCK" kill-server 2>/dev/null; rm -rf "$TEST_TMPDIR"' EXIT
T() { tmux -S "$SOCK" "$@"; }

start_server() {
    T -f /dev/null new-session -d -s s -n edit -x 80 -y 24
    T new-window -d -t s: -n ops
    T new-window -d -t s: -n 'tmux config'
    TM="$SOCK,$(T display -p '#{pid}'),0"
}
start_server

pane() { T display -p -t "$1" '#{pane_id}'; }
opt() { T display -p -t "$1" "#{$2}"; }

mklist() {
    local pending=${2:-0} todos="[]"
    if (( pending > 0 )); then
        todos=$(jq -n --argjson n "$pending" '[range($n) | {id: ("t\(.)"), text: "todo \(.)", done: false, order_index: .}]')
    fi
    jq -n --argjson todos "$todos" '{todos: $todos, _metadata: {}}' > "$DATA/lists/$1.json"
}

mklist work
mklist play 2
mklist daily 3

DEFAULT_SESSION='{"active_list": "work", "sessions": {"s:ops": "gone"}}'

# fresh fixture: session.json from $1 (default: one persisted link), no live links
reset() {
    printf '%s\n' "${1:-$DEFAULT_SESSION}" > "$DATA/session.json"
    local id
    for id in $(T list-windows -a -F '#{window_id}'); do
        T set -wqu -t "$id" @doit-window-list
        T set -wqu -t "$id" @doit-window-key
    done
}
reset

# run $1 (sourced helpers) inside window $2 of the test server; extra VAR=val pairs follow
in_win() {
    local fn_call="$1" win="$2"; shift 2
    env -u DOIT_ACTIVE_LIST -u DOIT_PINNED_LIST -u DOIT_WINDOW \
        TMUX="$TM" TMUX_PANE="$(pane "$win")" "$@" \
        bash -c "source '$SCRIPTS/get-active-list.sh'; $fn_call"
}
resolve_in() { local win="$1"; shift; in_win get_active_list_name "$win" "$@"; }

# run $1 with no tmux at all
no_tmux() {
    env -u TMUX -u TMUX_PANE -u DOIT_ACTIVE_LIST -u DOIT_WINDOW -u DOIT_PINNED_LIST "${@:2}" \
        bash -c "source '$SCRIPTS/get-active-list.sh'; $1"
}

persisted() { jq -r --arg k "$1" '.sessions[$k] // "null"' "$DATA/session.json"; }

# hooks run the relink script asynchronously; wait for the persisted key to settle
wait_persisted() {
    local i
    for i in $(seq 1 40); do
        [[ "$(persisted "$1")" == "$2" ]] && break
        sleep 0.05
    done
    persisted "$1"
}

describe "resolution chain"

it "a persisted link restores into its window's live option"
reset '{"active_list": "work", "sessions": {"s:edit": "play"}}'
assert_eq "play" "$(resolve_in s:edit)"
assert_eq "play" "$(opt s:edit @doit-window-list)"

it "DOIT_ACTIVE_LIST env beats the window link"
assert_eq "work" "$(resolve_in s:edit DOIT_ACTIVE_LIST=work)"

it "unlinked window inside tmux resolves daily, not the global pointer"
reset
assert_eq "daily" "$(resolve_in s:edit)"

it "a link to a deleted list is skipped, chain resolves daily"
assert_eq "daily" "$(resolve_in s:ops)"

it "daily is created when an unlinked window lands on it"
rm -f "$DATA/lists/daily.json"
assert_eq "daily" "$(resolve_in s:edit)"
assert_eq "daily exists" "$([[ -f "$DATA/lists/daily.json" ]] && echo 'daily exists')"
mklist daily 3

it "no tmux context resolves the global pointer"
assert_eq "work" "$(no_tmux get_active_list_name)"

it "no session file resolves daily"
rm -f "$DATA/session.json"
assert_eq "daily" "$(resolve_in s:edit)"

describe "pinned list (--list view)"

it "DOIT_PINNED_LIST wins over everything"
reset '{"active_list": "work", "sessions": {"s:edit": "play"}}'
assert_eq "daily" "$(resolve_in s:edit DOIT_PINNED_LIST=daily DOIT_ACTIVE_LIST=work)"

it "a pinned list that does not exist yet is created"
assert_eq "fresh" "$(no_tmux get_active_list_name DOIT_PINNED_LIST=fresh)"
assert_eq "fresh exists" "$([[ -f "$DATA/lists/fresh.json" ]] && echo 'fresh exists')"
rm -f "$DATA/lists/fresh.json"

it "--format under a pin renders the pinned list's todos"
OUT=$(env -u TMUX DOIT_PINNED_LIST=play \
    bash "$SCRIPTS/todo-interactive.sh" --format 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g')
assert_contains "$OUT" "todo 0"

describe "write helpers"

it "set_active_list in a window writes global, the live link, and its persisted copy"
reset '{"active_list": "daily", "sessions": {"s:ops": "play"}}'
in_win "set_active_list work" s:edit
assert_eq "work" "$(jq -r '.active_list' "$DATA/session.json")"
assert_eq "work" "$(opt s:edit @doit-window-list)"
assert_eq "work" "$(persisted s:edit)"
it "…and the other window's link survived (read-merge-write)"
assert_eq "play" "$(persisted s:ops)"

it "set_active_list outside tmux writes global only"
reset
no_tmux "set_active_list daily"
assert_eq "daily" "$(jq -r '.active_list' "$DATA/session.json")"
assert_eq "gone" "$(persisted s:ops)"

it "set_global_list never touches links, even in a window"
reset
in_win "set_global_list daily" s:edit
assert_eq "daily" "$(jq -r '.active_list' "$DATA/session.json")"
assert_eq "" "$(opt s:edit @doit-window-list)"
assert_eq "null" "$(persisted s:edit)"

it "unlink_current_window drops the live link and its persisted copy only"
reset '{"active_list": "work", "sessions": {"s:ops": "play"}}'
in_win "link_current_window play" s:edit
in_win "unlink_current_window" s:edit
assert_eq "" "$(opt s:edit @doit-window-list)"
assert_eq "null" "$(persisted s:edit)"
assert_eq "play" "$(persisted s:ops)"
it "…and the window does not re-adopt it"
assert_eq "daily" "$(resolve_in s:edit)"

it "link_window creates the sessions map when missing"
echo '{"active_list": "work"}' > "$DATA/session.json"
no_tmux "link_window s:gamma play"
assert_eq "play" "$(persisted s:gamma)"

it "set_active_list creates session.json when missing"
reset
rm -f "$DATA/session.json"
in_win "set_active_list play" s:edit
assert_eq "play" "$(jq -r '.active_list' "$DATA/session.json")"
assert_eq "play" "$(persisted s:edit)"

it "relink_windows_for_list follows a list rename, live and persisted"
reset '{"active_list": "work", "sessions": {"s:ops": "gone"}}'
in_win "link_current_window play" s:edit
in_win "relink_windows_for_list play renamed" s:edit
assert_eq "renamed" "$(opt s:edit @doit-window-list)"
assert_eq "renamed" "$(persisted s:edit)"
assert_eq "gone" "$(persisted s:ops)"

it "prune_links_for_list drops links to a deleted list, live and persisted"
reset
in_win "link_current_window play" s:edit
in_win "prune_links_for_list play" s:edit
assert_eq "" "$(opt s:edit @doit-window-list)"
assert_eq "null" "$(persisted s:edit)"
assert_eq "gone" "$(persisted s:ops)"

describe "windows_for_list"

it "lists the windows linked to a list"
reset '{"sessions": {"s:alpha": "play", "s:gamma": "play", "s:beta": "work"}}'
assert_eq "s:alpha s:gamma " "$(no_tmux "windows_for_list play" | sort | tr '\n' ' ')"

it "empty for an unlinked list"
assert_eq "" "$(no_tmux "windows_for_list daily")"

describe "per-window links"

it "two windows in one session resolve their own lists"
reset
in_win "link_current_window play" s:edit
in_win "link_current_window work" s:ops
assert_eq "play" "$(resolve_in s:edit)"
assert_eq "work" "$(resolve_in s:ops)"

it "a window name with spaces round-trips through link and lookup"
in_win "link_current_window play" 's:tmux config'
assert_eq "play" "$(resolve_in 's:tmux config')"
assert_eq "play" "$(persisted 's:tmux config')"

it "two windows with the same name keep their own lists"
reset
T new-window -d -t s: -n dup
T new-window -d -t s: -n dup
DUP1=$(T list-windows -t s -F '#{window_id} #{window_name}' | awk '$2 == "dup" {print $1}' | sed -n 1p)
DUP2=$(T list-windows -t s -F '#{window_id} #{window_name}' | awk '$2 == "dup" {print $1}' | sed -n 2p)
in_win "link_current_window play" "$DUP1"
in_win "link_current_window work" "$DUP2"
assert_eq "play" "$(resolve_in "$DUP1")"
assert_eq "work" "$(resolve_in "$DUP2")"
it "…and a third same-named window does not take either link"
T new-window -d -t s: -n dup
DUP3=$(T list-windows -t s -F '#{window_id} #{window_name}' | awk '$2 == "dup" {print $1}' | sed -n 3p)
assert_eq "daily" "$(resolve_in "$DUP3")"
T kill-window -t "$DUP1"; T kill-window -t "$DUP2"; T kill-window -t "$DUP3"

it "a legacy session-name link does not resolve on its own"
reset '{"active_list": "work", "sessions": {"s": "play"}}'
assert_eq "daily" "$(resolve_in s:edit)"

describe "links follow windows (hooks from doit.tmux)"

env TMUX="$TM" bash "$SCRIPTS/../doit.tmux" > /dev/null 2>&1

it "doit.tmux installs the relink hooks"
assert_contains "$(T show-hooks -gw)" "window-renamed[90]"

it "a renamed window keeps its list"
reset
in_win "link_current_window play" s:edit
T rename-window -t s:edit edit2
assert_eq "play" "$(resolve_in s:edit2)"
it "…and the persisted copy moves to the new name"
assert_eq "play" "$(wait_persisted s:edit2 play)"
assert_eq "null" "$(persisted s:edit)"

it "a window moved to another session keeps its list and persisted key follows"
T new-session -d -s other
T move-window -s s:edit2 -t other:
assert_eq "play" "$(resolve_in other:edit2)"
assert_eq "play" "$(wait_persisted other:edit2 play)"
assert_eq "null" "$(persisted s:edit2)"

it "a renamed session carries its windows' persisted keys"
T rename-session -t other other2
assert_eq "play" "$(wait_persisted other2:edit2 play)"
assert_eq "null" "$(persisted other:edit2)"
T move-window -s other2:edit2 -t s:
T rename-window -t s:edit2 edit
T kill-session -t other2

describe "tmux restart"

it "links come back from session.json after the server restarts"
reset
in_win "link_current_window play" s:edit
in_win "link_current_window work" s:ops
T kill-server
start_server
assert_eq "play" "$(resolve_in s:edit)"
assert_eq "work" "$(resolve_in s:ops)"
assert_eq "daily" "$(resolve_in 's:tmux config')"

it "after a restart, only one of two same-named windows takes the persisted link"
reset '{"active_list": "work", "sessions": {"s:dup": "play"}}'
T new-window -d -t s: -n dup
T new-window -d -t s: -n dup
DUPS=$(T list-windows -t s -F '#{window_id} #{window_name}' | awk '$2 == "dup" {print $1}')
GOT=""
for w in $DUPS; do GOT+="$(resolve_in "$w") "; done
assert_eq "daily play " "$(tr ' ' '\n' <<< "$GOT" | grep . | sort | tr '\n' ' ')"
for w in $DUPS; do T kill-window -t "$w"; done

describe "upgrade from per-session links (--migrate)"

it "a session link becomes a link on each of that session's windows"
reset '{"active_list": "work", "sessions": {"s": "play", "gone-session": "work"}}'
in_win "link_current_window work" s:ops
env TMUX="$TM" bash "$SCRIPTS/todo-relink.sh" --migrate
assert_eq "play" "$(opt s:edit @doit-window-list)"
assert_eq "play" "$(persisted s:edit)"
assert_eq "play" "$(persisted 's:tmux config')"
it "…a window with its own link keeps it"
assert_eq "work" "$(opt s:ops @doit-window-list)"
it "…the session key is gone"
assert_eq "null" "$(persisted s)"
it "…a key for a session that is not running stays for a later load"
assert_eq "work" "$(persisted gone-session)"

describe "window targeting"

it "a popup (no TMUX_PANE) resolves the window under it via the session id in \$TMUX"
reset
in_win "link_current_window play" s:edit
T select-window -t s:edit
SID=$(T display -p -t s '#{session_id}')
POPUP=$(env -u TMUX_PANE -u DOIT_WINDOW TMUX="$SOCK,1,${SID#\$}" \
    bash -c "source '$SCRIPTS/get-active-list.sh'; get_tmux_window_key")
assert_eq "s:edit" "$POPUP"

it "DOIT_WINDOW takes a window id (the status bar) or a session:window name (by hand)"
WID=$(T display -p -t s:edit '#{window_id}')
assert_eq "play" "$(env -u TMUX_PANE TMUX="$TM" DOIT_WINDOW="$WID" bash -c "source '$SCRIPTS/get-active-list.sh'; get_active_list_name")"
assert_eq "play" "$(env -u TMUX_PANE TMUX="$TM" DOIT_WINDOW="s:edit" bash -c "source '$SCRIPTS/get-active-list.sh'; get_active_list_name")"

report
