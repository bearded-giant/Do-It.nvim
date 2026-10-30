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
    make_list "$DOIT_DATA_DIR/lists/proj.json"

    OUT=$(bash "$SCRIPTS/todo-interactive.sh" --list proj --format 2>/dev/null)
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

# a note's todo_ids may name todos that were deleted or moved; readers skip those
make_links() {
    cat > "$1" <<'ENDJSON'
{
  "_metadata": { "updated_at": 1700000000 },
  "todos": [
    {"id":"t1","text":"claude: [bug] 3. fix the thing","done":false,"in_progress":false,"order_index":1},
    {"id":"t2","text":"plain task","done":false,"in_progress":false,"order_index":2},
    {"id":"t3","text":"unlinked task","done":false,"in_progress":false,"order_index":3}
  ],
  "notes": [
    {"id":"n1","title":"Plan","body":"steps","todo_ids":["t1","gone"],"created_at":1,"updated_at":1},
    {"id":"n2","title":"","body":"scratch first\nrest","todo_ids":["t1","t2"],"created_at":1,"updated_at":1},
    {"id":"n3","title":"Loose","body":"","created_at":1,"updated_at":1},
    {"id":"n4","title":"Dead","body":"","todo_ids":["gone"],"created_at":1,"updated_at":1}
  ]
}
ENDJSON
}

describe "preview_todo linked sections"

LINKS="$TEST_TMPDIR/links.json"
make_links "$LINKS"
sed -n '/^preview_todo() {/,/^}/p' "$SCRIPTS/todo-interactive.sh" > "$TEST_TMPDIR/preview_fn.sh"
eval "$(sed -n "/^DUE_JQ='/,/^'\$/p" "$SCRIPTS/todo-interactive.sh")"

# fresh bash, as fzf's --preview runs it
run_preview() {
    TODO_LIST_PATH="$LINKS" DUE_JQ="$DUE_JQ" bash -c "source '$TEST_TMPDIR/preview_fn.sh'; preview_todo '$1'" 2>&1
}

it "todo row lists linked note titles, untitled notes by first body line"
assert_contains "$(run_preview "fix the thing [t1]")" $'Notes:\n• Plan\n• scratch first'

it "todo row omits Notes when none link to it"
assert_eq "0" "$(run_preview "unlinked task [t3]" | grep -c '^Notes:')"

it "note row lists linked todo texts"
assert_contains "$(run_preview "Plan [note_n1]")" $'Todos:\n• claude: [bug] 3. fix the thing'

it "note row skips stale ids"
assert_eq "0" "$(run_preview "Plan [note_n1]" | grep -c 'gone')"

it "note row omits Todos when it has no links"
assert_eq "0" "$(run_preview "Loose [note_n3]" | grep -c '^Todos:')"

it "note row omits Todos when every link is stale"
assert_eq "0" "$(run_preview "Dead [note_n4]" | grep -c '^Todos:')"

# fake fzf replays one scripted key/answer per call and records what it was offered;
# nvim and tmux stubs keep the scripts off a real editor and the user's tmux server
FAKE_BIN="$TEST_TMPDIR/bin"
STUB_DIR="$TEST_TMPDIR/stub"
mkdir -p "$FAKE_BIN"
cat > "$FAKE_BIN/fzf" <<'EOF'
#!/bin/bash
n=$(( $(cat "$STUB_DIR/calls" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$STUB_DIR/calls"
cat > "$STUB_DIR/rows.$n"
printf '%s\n' "$@" > "$STUB_DIR/args.$n"
printf '%b\n' "$(sed -n "${n}p" "$STUB_DIR/keys")"
EOF
printf '#!/bin/bash\nexit 0\n' > "$FAKE_BIN/nvim"
printf '#!/bin/bash\nexit 0\n' > "$FAKE_BIN/tmux"
chmod +x "$FAKE_BIN"/*

notes_cli() {
    rm -rf "$STUB_DIR"; mkdir -p "$STUB_DIR"
    printf '%s\n' "$@" > "$STUB_DIR/keys"
}
run_notes() {
    env -u TMUX -u TMUX_PANE PATH="$FAKE_BIN:$PATH" STUB_DIR="$STUB_DIR" EDITOR=nvim TERM=dumb \
        DOIT_DATA_DIR="$TEST_TMPDIR/ndata" DOIT_PINNED_LIST=links \
        bash "$SCRIPTS/todo-notes.sh" "$@" </dev/null >/dev/null 2>&1
}
mkdir -p "$TEST_TMPDIR/ndata/lists"
NLIST="$TEST_TMPDIR/ndata/lists/links.json"

describe "todo-notes.sh --todo"

make_links "$NLIST"
notes_cli "Linked title"
run_notes --todo t2 --new

it "--new creates a note linked to the todo"
assert_eq '["t2"]' "$(jq -c '.notes[] | select(.title == "Linked title") | .todo_ids' "$NLIST")"

it "--new leaves the other notes and todos intact"
assert_eq "5 3" "$(jq -r '"\(.notes | length) \(.todos | length)"' "$NLIST")"

it "plain --new still creates an unlinked note"
notes_cli "Free note"
run_notes --new
assert_eq "null" "$(jq -c '.notes[] | select(.title == "Free note") | .todo_ids' "$NLIST")"

it "--todo with an unknown id exits non-zero and writes nothing"
make_links "$NLIST"
notes_cli "Nope"
run_notes --todo missing --new
status=$?
assert_eq "1 4" "$status $(jq '.notes | length' "$NLIST")"

make_links "$NLIST"
notes_cli a q
run_notes --todo t2

it "modal starts on notes linked to the todo"
assert_eq "[n2]" "$(sed 's/\x1b\[[0-9;]*m//g' "$STUB_DIR/rows.1" | grep -oE '\[[^]]+\]$' | tr '\n' ' ' | sed 's/ $//')"

it "header names the todo and the toggle key"
assert_contains "$(cat "$STUB_DIR/args.1")" "todo: plain task (linked only)"
assert_contains "$(cat "$STUB_DIR/args.1")" "a: All notes"

it "a toggles to every note on the list"
assert_eq "[n1] [n2] [n3] [n4]" "$(sed 's/\x1b\[[0-9;]*m//g' "$STUB_DIR/rows.2" | grep -oE '\[[^]]+\]$' | tr '\n' ' ' | sed 's/ $//')"
assert_contains "$(cat "$STUB_DIR/args.2")" "a: Linked only"

make_links "$NLIST"
notes_cli a 'l\n• Loose  [n3]' 'l\n• Loose  [n3]' q
run_notes --todo t2

it "all-notes view marks the notes linked to the todo"
assert_eq "● [n2]" "$(sed 's/\x1b\[[0-9;]*m//g' "$STUB_DIR/rows.2" | grep -E '\[n2\]$' | sed -E 's/^(●).*(\[n2\])$/\1 \2/')"

it "l links the selected note to the todo"
assert_eq "● [n3]" "$(sed 's/\x1b\[[0-9;]*m//g' "$STUB_DIR/rows.3" | grep -E '\[n3\]$' | sed -E 's/^(●).*(\[n3\])$/\1 \2/')"

it "l again unlinks it and drops the empty field"
assert_eq "null" "$(jq -c '.notes[] | select(.id == "n3") | .todo_ids' "$NLIST")"

if command -v fzf &>/dev/null; then
    describe "note rows show a linked-todo count (todo-interactive.sh --format)"

    export DOIT_DATA_DIR="$TEST_TMPDIR/data"
    make_links "$DOIT_DATA_DIR/lists/links.json"
    STRIPPED=$(bash "$SCRIPTS/todo-interactive.sh" --list links --format 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g')

    it "counts live links only"
    assert_contains "$(grep '\[note_n1\]$' <<< "$STRIPPED")" "(1 todo)"

    it "pluralizes"
    assert_contains "$(grep '\[note_n2\]$' <<< "$STRIPPED")" "(2 todos)"

    it "no marker on unlinked or all-stale notes"
    assert_eq "0" "$(grep -E '\[note_n[34]\]$' <<< "$STRIPPED" | grep -c 'todo')"
fi

report
