#!/bin/bash

# tests for list-scoped scratch notes: data integrity (jq read-modify-write)
# and render placement (Notes section between pending and completed).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_harness.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCRIPTS="$REPO_ROOT/tmux/scripts"

make_list() {
    local path="$1"
    cat > "$path" <<'ENDJSON'
{
  "_metadata": { "updated_at": 1700000000 },
  "todos": [
    {"id":"t1","text":"crit task","priorities":"critical","done":false,"in_progress":false,"order_index":1},
    {"id":"t2","text":"plain task","done":false,"in_progress":false,"order_index":2},
    {"id":"t3","text":"finished","done":true,"in_progress":false,"order_index":3,"completed_at":1700000100}
  ],
  "notes": [
    {"id":"n1","title":"Buy milk","body":"2%\nfrom store","created_at":1,"updated_at":1}
  ]
}
ENDJSON
}

# the same jq the scripts use, kept in sync with todo-notes.sh / todo-interactive.sh
add_note()    { jq --arg id "$2" --arg t "$3" --arg b "$4" '.notes = ((.notes // []) + [{id:$id,title:$t,body:$b,created_at:(now|floor),updated_at:(now|floor)}]) | ._metadata.updated_at=(now|floor)' "$1" > "$1.tmp" && mv "$1.tmp" "$1"; }
edit_note()   { jq --arg id "$2" --arg t "$3" --arg b "$4" '.notes |= map(if .id==$id then .title=$t|.body=$b|.updated_at=(now|floor) else . end) | ._metadata.updated_at=(now|floor)' "$1" > "$1.tmp" && mv "$1.tmp" "$1"; }
delete_note() { jq --arg id "$2" '.notes |= map(select(.id != $id)) | ._metadata.updated_at=(now|floor)' "$1" > "$1.tmp" && mv "$1.tmp" "$1"; }
render_note() { jq -r '(.notes // []) | .[] | (if (.title // "") == "" then ((.body // "") | split("\n")[0]) else (.title) end) as $t | "\(.id)|\($t)"' "$1"; }

describe "list notes data model"

LIST="$TEST_TMPDIR/daily.json"
make_list "$LIST"

it "renders note title in the notes section"
assert_eq "n1|Buy milk" "$(render_note "$LIST")"

it "falls back to first body line when title empty"
echo '{"notes":[{"id":"x","title":"","body":"scratch line\nmore"}]}' > "$TEST_TMPDIR/nt.json"
assert_eq "x|scratch line" "$(render_note "$TEST_TMPDIR/nt.json")"

it "legacy list without notes key yields zero notes"
echo '{"_metadata":{},"todos":[]}' > "$TEST_TMPDIR/legacy.json"
assert_eq "0" "$(jq '(.notes // []) | length' "$TEST_TMPDIR/legacy.json")"

it "ADD appends a note and leaves todos intact"
add_note "$LIST" "n2" "Standup" "9am daily"
assert_eq "2" "$(jq '.notes | length' "$LIST")"
assert_eq "3" "$(jq '.todos | length' "$LIST")"
assert_eq "Standup" "$(jq -r '.notes[] | select(.id=="n2") | .title' "$LIST")"

it "EDIT updates title and body of the target note only"
edit_note "$LIST" "n1" "Buy oat milk" "barista edition"
assert_eq "Buy oat milk" "$(jq -r '.notes[] | select(.id=="n1") | .title' "$LIST")"
assert_eq "barista edition" "$(jq -r '.notes[] | select(.id=="n1") | .body' "$LIST")"
assert_eq "Standup" "$(jq -r '.notes[] | select(.id=="n2") | .title' "$LIST")"

it "DELETE removes only the target note"
delete_note "$LIST" "n2"
assert_eq "1" "$(jq '.notes | length' "$LIST")"
assert_eq "n1" "$(jq -r '.notes[0].id' "$LIST")"
assert_eq "3" "$(jq '.todos | length' "$LIST")"

# render placement test needs fzf (todo-interactive.sh hard-requires it)
if command -v fzf &>/dev/null; then
    describe "render placement (todo-interactive.sh --format)"

    export DOIT_DATA_DIR="$TEST_TMPDIR/data"
    mkdir -p "$DOIT_DATA_DIR/lists"
    make_list "$DOIT_DATA_DIR/lists/daily.json"
    echo '{"active_list":"daily"}' > "$DOIT_DATA_DIR/session.json"

    OUT=$(bash "$SCRIPTS/todo-interactive.sh" --format 2>/dev/null)
    STRIPPED=$(echo "$OUT" | sed 's/\x1b\[[0-9;]*m//g')

    it "renders a pending priority header"
    assert_contains "$STRIPPED" "Critical"

    it "renders a Notes header"
    assert_contains "$STRIPPED" "Notes"

    it "tags note rows with [note_<id>]"
    assert_contains "$STRIPPED" "[note_n1]"

    it "places Notes section after pending and before completed"
    notes_ln=$(echo "$STRIPPED" | grep -n '^Notes$' | head -1 | cut -d: -f1)
    pending_ln=$(echo "$STRIPPED" | grep -n 'plain task' | head -1 | cut -d: -f1)
    done_ln=$(echo "$STRIPPED" | grep -n 'finished' | head -1 | cut -d: -f1)
    if [[ -n "$notes_ln" && -n "$pending_ln" && -n "$done_ln" && "$pending_ln" -lt "$notes_ln" && "$notes_ln" -lt "$done_ln" ]]; then
        assert_eq "ok" "ok"
    else
        assert_eq "pending<notes<done" "pending=$pending_ln notes=$notes_ln done=$done_ln"
    fi
fi

report
