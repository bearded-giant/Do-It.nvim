#!/bin/bash

# per-tmux-session active list: resolution chain, link read/write helpers, and
# the pinned (--list) view. sessions map lives in session.json next to the
# global .active_list pointer; DOIT_SESSION_NAME fakes the tmux session name.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_harness.sh"

SCRIPTS="$SCRIPT_DIR/../../tmux/scripts"
DATA="$TEST_TMPDIR/data"
mkdir -p "$DATA/lists"

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

reset_session() {
    cat > "$DATA/session.json" << 'EOF'
{"active_list": "work", "timestamp": 1, "sessions": {"alpha": "play", "beta": "gone"}}
EOF
}
reset_session

# resolve the active list under a controlled env; extra VAR=val pairs go first
resolve() {
    env -u TMUX -u DOIT_ACTIVE_LIST -u DOIT_SESSION_NAME -u DOIT_PINNED_LIST \
        DOIT_DATA_DIR="$DATA" "$@" \
        bash -c "source '$SCRIPTS/get-active-list.sh'; get_active_list_name"
}

# run a sourced helper function under the fixture data dir
helper() {
    local fn_call="$1"; shift
    env -u TMUX -u DOIT_ACTIVE_LIST -u DOIT_SESSION_NAME -u DOIT_PINNED_LIST \
        DOIT_DATA_DIR="$DATA" "$@" \
        bash -c "source '$SCRIPTS/get-active-list.sh'; $fn_call"
}

describe "resolution chain"

it "linked session resolves its linked list"
assert_eq "play" "$(resolve DOIT_SESSION_NAME=alpha)"

it "DOIT_ACTIVE_LIST env beats the session link"
assert_eq "work" "$(resolve DOIT_SESSION_NAME=alpha DOIT_ACTIVE_LIST=work)"

it "unlinked session falls back to the global pointer"
assert_eq "work" "$(resolve DOIT_SESSION_NAME=unknown)"

it "a link to a deleted list is skipped, chain resolves global"
assert_eq "work" "$(resolve DOIT_SESSION_NAME=beta)"

it "no tmux context resolves the global pointer exactly like before"
assert_eq "work" "$(resolve)"

it "no session file resolves daily"
mv "$DATA/session.json" "$DATA/session.json.bak"
assert_eq "daily" "$(resolve DOIT_SESSION_NAME=alpha)"
mv "$DATA/session.json.bak" "$DATA/session.json"

describe "pinned list (--list view)"

it "DOIT_PINNED_LIST wins over everything"
assert_eq "daily" "$(resolve DOIT_PINNED_LIST=daily DOIT_ACTIVE_LIST=work DOIT_SESSION_NAME=alpha)"

it "a pinned list that does not exist yet is created"
assert_eq "fresh" "$(resolve DOIT_PINNED_LIST=fresh)"
assert_eq "fresh exists" "$([[ -f "$DATA/lists/fresh.json" ]] && echo 'fresh exists')"
rm -f "$DATA/lists/fresh.json"

it "todo-interactive.sh --list pins the popup to that list"
HEADER_LIST=$(env -u TMUX DOIT_DATA_DIR="$DATA" bash -c "
    source '$SCRIPTS/get-active-list.sh'
    export DOIT_PINNED_LIST=daily
    get_active_list_name")
assert_eq "daily" "$HEADER_LIST"

it "--format under a pin renders the pinned list's todos"
OUT=$(env -u TMUX DOIT_DATA_DIR="$DATA" DOIT_PINNED_LIST=play \
    bash "$SCRIPTS/todo-interactive.sh" --format 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g')
assert_contains "$OUT" "todo 0"

describe "write helpers"

it "set_active_list with a session writes global AND the link"
reset_session
helper "set_active_list work" DOIT_SESSION_NAME=alpha
assert_eq "work" "$(jq -r '.active_list' "$DATA/session.json")"
it "…the session link updated too"
assert_eq "work" "$(jq -r '.sessions.alpha' "$DATA/session.json")"
it "…and the other session's link survived (read-merge-write)"
assert_eq "gone" "$(jq -r '.sessions.beta' "$DATA/session.json")"

it "set_active_list outside tmux writes global only"
reset_session
helper "set_active_list daily"
assert_eq "daily" "$(jq -r '.active_list' "$DATA/session.json")"
it "…links untouched"
assert_eq "play" "$(jq -r '.sessions.alpha' "$DATA/session.json")"

it "set_global_list never touches links, even with a session"
reset_session
helper "set_global_list daily" DOIT_SESSION_NAME=alpha
assert_eq "daily" "$(jq -r '.active_list' "$DATA/session.json")"
assert_eq "play" "$(jq -r '.sessions.alpha' "$DATA/session.json")"

it "unlink_session drops only that session's link"
reset_session
helper "unlink_session alpha"
assert_eq "null" "$(jq -r '.sessions.alpha' "$DATA/session.json")"
assert_eq "gone" "$(jq -r '.sessions.beta' "$DATA/session.json")"
assert_eq "work" "$(jq -r '.active_list' "$DATA/session.json")"

it "link_session creates the sessions map when missing"
echo '{"active_list": "work"}' > "$DATA/session.json"
helper "link_session gamma play"
assert_eq "play" "$(jq -r '.sessions.gamma' "$DATA/session.json")"

it "set_active_list creates session.json when missing"
rm -f "$DATA/session.json"
helper "set_active_list play" DOIT_SESSION_NAME=alpha
assert_eq "play" "$(jq -r '.active_list' "$DATA/session.json")"
assert_eq "play" "$(jq -r '.sessions.alpha' "$DATA/session.json")"

it "relink_sessions_for_list follows a rename"
reset_session
helper "relink_sessions_for_list play renamed"
assert_eq "renamed" "$(jq -r '.sessions.alpha' "$DATA/session.json")"
assert_eq "gone" "$(jq -r '.sessions.beta' "$DATA/session.json")"

it "prune_links_for_list drops links to a deleted list"
reset_session
helper "prune_links_for_list play"
assert_eq "null" "$(jq -r '.sessions.alpha' "$DATA/session.json")"
assert_eq "gone" "$(jq -r '.sessions.beta' "$DATA/session.json")"

describe "sessions_for_list"

it "lists the sessions linked to a list"
reset_session
helper "link_session gamma play" > /dev/null
LINKED=$(helper "sessions_for_list play" | sort | tr '\n' ' ')
assert_eq "alpha gamma " "$LINKED"

it "empty for an unlinked list"
assert_eq "" "$(helper "sessions_for_list work")"

report
