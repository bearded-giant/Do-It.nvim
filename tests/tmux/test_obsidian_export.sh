#!/bin/bash

# tests for the O keybind: send todo to obsidian daily note
# exercises the core logic extracted from todo-interactive.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_harness.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# -- helpers --

make_todo_list() {
    local path="$1"
    local todo_id="$2"
    local todo_text="$3"
    cat > "$path" <<ENDJSON
{
  "todos": [
    {
      "id": "$todo_id",
      "text": "$todo_text",
      "done": false,
      "in_progress": false,
      "order_index": 1,
      "created_at": 1700000000
    }
  ],
  "_metadata": {
    "updated_at": 1700000000
  }
}
ENDJSON
}

make_daily_note() {
    local path="$1"
    cat > "$path" <<'ENDMD'
# 2026-02-22

## Meetings
- standup at 9

## TODO
- [ ] - existing task

---

## Notes
some notes here
ENDMD
}

make_daily_note_no_separator() {
    local path="$1"
    cat > "$path" <<'ENDMD'
# 2026-02-22

## TODO
- [ ] - existing task
ENDMD
}

make_daily_note_next_heading() {
    local path="$1"
    cat > "$path" <<'ENDMD'
# 2026-02-22

## TODO
- [ ] - existing task

## Notes
some notes here
ENDMD
}

make_daily_note_empty_todo() {
    local path="$1"
    cat > "$path" <<'ENDMD'
# 2026-02-22

## TODO

---

## Notes
ENDMD
}

# core export logic matching todo-interactive.sh (single-pass awk)
# takes: TODO_ID, TODO_TEXT, DAILY_PATH, TODO_LIST_PATH
# returns: 0 on success, 1 on error; prints messages to stdout
run_export() {
    local TODO_ID="$1"
    local TODO_TEXT="$2"
    local DAILY_PATH="$3"
    local TODO_LIST_PATH="$4"
    local SECTION_MARKER="${5:-## TODO}"
    local TODAY="2026-02-22"

    # check if already linked
    local HAS_REF
    HAS_REF=$(jq -r --arg id "$TODO_ID" '.todos[] | select(.id == $id) | .obsidian_ref // empty' "$TODO_LIST_PATH")
    if [[ -n "$HAS_REF" ]]; then
        echo "Already linked to daily note"
        return 1
    fi

    if [[ ! -f "$DAILY_PATH" ]]; then
        echo "Today's daily note not found: $DAILY_PATH"
        return 1
    fi

    local NEW_LINE="- [ ] - $TODO_TEXT <!-- doit:$TODO_ID -->"

    # single-pass: insert right after section heading
    awk -v line="$NEW_LINE" -v marker="$SECTION_MARKER" '
        index($0, marker) == 1 { print; print line; inserted=1; next }
        { print }
        END { if (!inserted) print "ERROR: no " marker " section" > "/dev/stderr" }
    ' "$DAILY_PATH" > "${DAILY_PATH}.tmp"

    if ! grep -qF "$SECTION_MARKER" "${DAILY_PATH}.tmp"; then
        echo "No $SECTION_MARKER section found in daily note"
        rm -f "${DAILY_PATH}.tmp"
        return 1
    fi

    # check stderr sentinel for missing section
    if ! grep -qF "$SECTION_MARKER" "$DAILY_PATH"; then
        echo "No $SECTION_MARKER section found in daily note"
        rm -f "${DAILY_PATH}.tmp"
        return 1
    fi

    mv "${DAILY_PATH}.tmp" "$DAILY_PATH"

    # set obsidian_ref (lnum 0 — nvim refresh_buffer_refs derives real value)
    jq --arg id "$TODO_ID" --arg date "$TODAY" --arg file "$DAILY_PATH" '
        .todos |= map(
            if .id == $id then
                .obsidian_ref = { file: $file, date: $date, lnum: 0 }
            else . end
        ) |
        ._metadata.updated_at = (now | floor)
    ' "$TODO_LIST_PATH" > "${TODO_LIST_PATH}.tmp" && mv "${TODO_LIST_PATH}.tmp" "$TODO_LIST_PATH"

    echo "Sent to daily: $TODO_TEXT"
    return 0
}

# -- full export tests --

describe "obsidian export: basic flow"

it "inserts todo into daily note"
DAILY="$TEST_TMPDIR/export_basic.md"
TODOLIST="$TEST_TMPDIR/export_basic.json"
make_daily_note "$DAILY"
make_todo_list "$TODOLIST" "abc123" "test sync"
run_export "abc123" "test sync" "$DAILY" "$TODOLIST" > /dev/null
assert_file_contains "$DAILY" "- [ ] - test sync <!-- doit:abc123 -->"

it "inserts immediately after ## TODO heading"
DAILY="$TEST_TMPDIR/export_after_heading.md"
TODOLIST="$TEST_TMPDIR/export_after_heading.json"
make_daily_note "$DAILY"
make_todo_list "$TODOLIST" "pos123" "positioned todo"
run_export "pos123" "positioned todo" "$DAILY" "$TODOLIST" > /dev/null
# the line right after ## TODO should be the new todo
LINE_AFTER=$(awk '/^## TODO/ { getline; print; exit }' "$DAILY")
assert_eq "- [ ] - positioned todo <!-- doit:pos123 -->" "$LINE_AFTER" "should be first line after ## TODO"

it "preserves existing todos after the inserted line"
DAILY="$TEST_TMPDIR/export_order.md"
TODOLIST="$TEST_TMPDIR/export_order.json"
make_daily_note "$DAILY"
make_todo_list "$TODOLIST" "abc123" "new todo"
run_export "abc123" "new todo" "$DAILY" "$TODOLIST" > /dev/null
assert_file_contains "$DAILY" "- [ ] - existing task"
assert_file_contains "$DAILY" "- [ ] - new todo <!-- doit:abc123 -->"
assert_file_contains "$DAILY" "---"

it "sets obsidian_ref on the todo json"
DAILY="$TEST_TMPDIR/export_ref.md"
TODOLIST="$TEST_TMPDIR/export_ref.json"
make_daily_note "$DAILY"
make_todo_list "$TODOLIST" "ref123" "check ref"
run_export "ref123" "check ref" "$DAILY" "$TODOLIST" > /dev/null
REF_DATE=$(jq -r '.todos[0].obsidian_ref.date' "$TODOLIST")
assert_eq "2026-02-22" "$REF_DATE" "obsidian_ref.date should be today"

it "obsidian_ref.lnum is 0 (nvim derives real value)"
DAILY="$TEST_TMPDIR/export_lnum.md"
TODOLIST="$TEST_TMPDIR/export_lnum.json"
make_daily_note "$DAILY"
make_todo_list "$TODOLIST" "lnum123" "check lnum"
run_export "lnum123" "check lnum" "$DAILY" "$TODOLIST" > /dev/null
LNUM=$(jq -r '.todos[0].obsidian_ref.lnum' "$TODOLIST")
assert_eq "0" "$LNUM" "lnum should be 0"

describe "obsidian export: prevents duplicates"

it "rejects export when obsidian_ref already exists"
DAILY="$TEST_TMPDIR/export_dup.md"
TODOLIST="$TEST_TMPDIR/export_dup.json"
make_daily_note "$DAILY"
# pre-set obsidian_ref
cat > "$TODOLIST" <<'ENDJSON'
{
  "todos": [
    {
      "id": "dup123",
      "text": "already linked",
      "done": false,
      "in_progress": false,
      "order_index": 1,
      "obsidian_ref": { "file": "/some/path.md", "date": "2026-02-21", "lnum": 5 }
    }
  ],
  "_metadata": { "updated_at": 1700000000 }
}
ENDJSON
OUTPUT=$(run_export "dup123" "already linked" "$DAILY" "$TODOLIST")
assert_contains "$OUTPUT" "Already linked"

describe "obsidian export: edge cases"

it "handles todo text with special characters (slashes, ampersands)"
DAILY="$TEST_TMPDIR/export_special.md"
TODOLIST="$TEST_TMPDIR/export_special.json"
make_daily_note "$DAILY"
make_todo_list "$TODOLIST" "sp123" 'fix path/to/file & cleanup'
run_export "sp123" 'fix path/to/file & cleanup' "$DAILY" "$TODOLIST" > /dev/null
assert_file_contains "$DAILY" "fix path/to/file & cleanup <!-- doit:sp123 -->"

it "handles empty ## TODO section (no existing items)"
DAILY="$TEST_TMPDIR/export_empty.md"
TODOLIST="$TEST_TMPDIR/export_empty.json"
make_daily_note_empty_todo "$DAILY"
make_todo_list "$TODOLIST" "empty123" "first todo"
run_export "empty123" "first todo" "$DAILY" "$TODOLIST" > /dev/null
assert_file_contains "$DAILY" "- [ ] - first todo <!-- doit:empty123 -->"
# separator should still follow
assert_file_contains "$DAILY" "---"

it "handles daily note with ## heading terminator instead of ---"
DAILY="$TEST_TMPDIR/export_heading.md"
TODOLIST="$TEST_TMPDIR/export_heading.json"
make_daily_note_next_heading "$DAILY"
make_todo_list "$TODOLIST" "hd123" "heading test"
run_export "hd123" "heading test" "$DAILY" "$TODOLIST" > /dev/null
assert_file_contains "$DAILY" "- [ ] - heading test <!-- doit:hd123 -->"
# ## Notes should still be there
assert_file_contains "$DAILY" "## Notes"

it "handles daily note with no terminator (TODO at end of file)"
DAILY="$TEST_TMPDIR/export_noterm.md"
TODOLIST="$TEST_TMPDIR/export_noterm.json"
make_daily_note_no_separator "$DAILY"
make_todo_list "$TODOLIST" "nt123" "end of file"
run_export "nt123" "end of file" "$DAILY" "$TODOLIST" > /dev/null
assert_file_contains "$DAILY" "- [ ] - end of file <!-- doit:nt123 -->"

it "fails gracefully when daily note is missing"
TODOLIST="$TEST_TMPDIR/export_missing.json"
make_todo_list "$TODOLIST" "miss123" "no daily"
OUTPUT=$(run_export "miss123" "no daily" "$TEST_TMPDIR/nonexistent.md" "$TODOLIST")
assert_contains "$OUTPUT" "not found"

it "fails gracefully when no ## TODO section exists"
DAILY="$TEST_TMPDIR/export_nosection.md"
TODOLIST="$TEST_TMPDIR/export_nosection.json"
cat > "$DAILY" <<'EOF'
# 2026-02-22
## Meetings
- standup
EOF
make_todo_list "$TODOLIST" "ns123" "no section"
OUTPUT=$(run_export "ns123" "no section" "$DAILY" "$TODOLIST")
assert_contains "$OUTPUT" "No ## TODO section"

describe "obsidian export: preserved file structure"

it "preserves all sections after export"
DAILY="$TEST_TMPDIR/export_structure.md"
TODOLIST="$TEST_TMPDIR/export_structure.json"
make_daily_note "$DAILY"
make_todo_list "$TODOLIST" "str123" "structure test"
run_export "str123" "structure test" "$DAILY" "$TODOLIST" > /dev/null
assert_file_contains "$DAILY" "## Meetings"
assert_file_contains "$DAILY" "- standup at 9"
assert_file_contains "$DAILY" "## TODO"
assert_file_contains "$DAILY" "## Notes"
assert_file_contains "$DAILY" "some notes here"

describe "obsidian export: configurable section marker"

it "inserts todo using custom section marker"
DAILY="$TEST_TMPDIR/export_custom_marker.md"
TODOLIST="$TEST_TMPDIR/export_custom_marker.json"
cat > "$DAILY" <<'ENDMD'
# 2026-02-22

## Meetings
- standup at 9

## Tasks
- [ ] - existing task

---

## Notes
some notes here
ENDMD
make_todo_list "$TODOLIST" "cm123" "custom marker todo"
run_export "cm123" "custom marker todo" "$DAILY" "$TODOLIST" "## Tasks" > /dev/null
assert_file_contains "$DAILY" "- [ ] - custom marker todo <!-- doit:cm123 -->"
# verify it went right after ## Tasks, not somewhere random
LINE_AFTER=$(awk '/^## Tasks/ { getline; print; exit }' "$DAILY")
assert_eq "- [ ] - custom marker todo <!-- doit:cm123 -->" "$LINE_AFTER" "should be first line after ## Tasks"

it "default marker still works when not specified"
DAILY="$TEST_TMPDIR/export_default_marker.md"
TODOLIST="$TEST_TMPDIR/export_default_marker.json"
make_daily_note "$DAILY"
make_todo_list "$TODOLIST" "dm123" "default marker todo"
run_export "dm123" "default marker todo" "$DAILY" "$TODOLIST" > /dev/null
assert_file_contains "$DAILY" "- [ ] - default marker todo <!-- doit:dm123 -->"
LINE_AFTER=$(awk '/^## TODO/ { getline; print; exit }' "$DAILY")
assert_eq "- [ ] - default marker todo <!-- doit:dm123 -->" "$LINE_AFTER" "should be first line after ## TODO"

it "fails when custom marker section is missing"
DAILY="$TEST_TMPDIR/export_missing_marker.md"
TODOLIST="$TEST_TMPDIR/export_missing_marker.json"
make_daily_note "$DAILY"
make_todo_list "$TODOLIST" "mm123" "missing marker"
OUTPUT=$(run_export "mm123" "missing marker" "$DAILY" "$TODOLIST" "## Tasks")
assert_contains "$OUTPUT" "No ## Tasks section"

describe "obsidian export: custom daily note path"

it "works with daily note in a non-standard directory"
mkdir -p "$TEST_TMPDIR/vault/journal/2026/02"
DAILY="$TEST_TMPDIR/vault/journal/2026/02/2026-02-22.md"
TODOLIST="$TEST_TMPDIR/export_custom_path.json"
make_daily_note "$DAILY"
make_todo_list "$TODOLIST" "cp123" "custom path todo"
run_export "cp123" "custom path todo" "$DAILY" "$TODOLIST" > /dev/null
assert_file_contains "$DAILY" "- [ ] - custom path todo <!-- doit:cp123 -->"

it "works with daily note using alternate naming"
mkdir -p "$TEST_TMPDIR/vault/logs"
DAILY="$TEST_TMPDIR/vault/logs/2026-02-22-daily.md"
TODOLIST="$TEST_TMPDIR/export_alt_name.json"
make_daily_note "$DAILY"
make_todo_list "$TODOLIST" "an123" "alt name todo"
run_export "an123" "alt name todo" "$DAILY" "$TODOLIST" > /dev/null
assert_file_contains "$DAILY" "- [ ] - alt name todo <!-- doit:an123 -->"

describe "obsidian export: lookback resolution"

# helper: resolve daily path with lookback (mirrors tmux logic)
resolve_daily_path() {
    local VAULT_PATH="$1"
    local DAILY_TEMPLATE="$2"
    local LOOKBACK_DAYS="${3:-7}"

    local DAILY_PATH="$VAULT_PATH/$(date +"$DAILY_TEMPLATE")"
    if [[ -f "$DAILY_PATH" ]]; then
        echo "$DAILY_PATH"
        return 0
    fi

    if [[ "$LOOKBACK_DAYS" -gt 0 ]]; then
        for i in $(seq 1 "$LOOKBACK_DAYS"); do
            local PAST_PATH="$VAULT_PATH/$(date -v-${i}d +"$DAILY_TEMPLATE" 2>/dev/null || date -d "-${i} days" +"$DAILY_TEMPLATE")"
            if [[ -f "$PAST_PATH" ]]; then
                echo "$PAST_PATH"
                return 0
            fi
        done
    fi

    # nothing found, return today's path
    echo "$DAILY_PATH"
    return 1
}

it "resolves today's note when it exists"
mkdir -p "$TEST_TMPDIR/lb_vault/daily"
TODAY_FILE="$TEST_TMPDIR/lb_vault/daily/$(date +%Y-%m-%d).md"
make_daily_note "$TODAY_FILE"
RESOLVED=$(resolve_daily_path "$TEST_TMPDIR/lb_vault" "daily/%Y-%m-%d.md" 7)
assert_eq "$TODAY_FILE" "$RESOLVED" "should resolve to today's note"

it "falls back to yesterday when today is missing"
mkdir -p "$TEST_TMPDIR/lb_vault2/daily"
YESTERDAY_FILE="$TEST_TMPDIR/lb_vault2/daily/$(date -v-1d +%Y-%m-%d 2>/dev/null || date -d '-1 day' +%Y-%m-%d).md"
make_daily_note "$YESTERDAY_FILE"
RESOLVED=$(resolve_daily_path "$TEST_TMPDIR/lb_vault2" "daily/%Y-%m-%d.md" 7)
assert_eq "$YESTERDAY_FILE" "$RESOLVED" "should fall back to yesterday's note"

it "returns today's path when nothing found within lookback"
mkdir -p "$TEST_TMPDIR/lb_vault3/daily"
# no files at all
RESOLVED=$(resolve_daily_path "$TEST_TMPDIR/lb_vault3" "daily/%Y-%m-%d.md" 3)
EXPECTED="$TEST_TMPDIR/lb_vault3/daily/$(date +%Y-%m-%d).md"
assert_eq "$EXPECTED" "$RESOLVED" "should return today's path as fallback"

it "skips lookback when lookback_days is 0"
mkdir -p "$TEST_TMPDIR/lb_vault4/daily"
YESTERDAY_FILE="$TEST_TMPDIR/lb_vault4/daily/$(date -v-1d +%Y-%m-%d 2>/dev/null || date -d '-1 day' +%Y-%m-%d).md"
make_daily_note "$YESTERDAY_FILE"
RESOLVED=$(resolve_daily_path "$TEST_TMPDIR/lb_vault4" "daily/%Y-%m-%d.md" 0)
EXPECTED="$TEST_TMPDIR/lb_vault4/daily/$(date +%Y-%m-%d).md"
assert_eq "$EXPECTED" "$RESOLVED" "should not look back when lookback is 0"

it "lookback works with custom path template"
mkdir -p "$TEST_TMPDIR/lb_vault5/journal"
YESTERDAY_FILE="$TEST_TMPDIR/lb_vault5/journal/$(date -v-1d +%Y-%m-%d 2>/dev/null || date -d '-1 day' +%Y-%m-%d)-daily.md"
make_daily_note "$YESTERDAY_FILE"
RESOLVED=$(resolve_daily_path "$TEST_TMPDIR/lb_vault5" "journal/%Y-%m-%d-daily.md" 7)
assert_eq "$YESTERDAY_FILE" "$RESOLVED" "should find yesterday's note with custom template"

# -- done --

report
