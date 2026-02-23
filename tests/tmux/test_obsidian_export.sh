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

# core export logic matching todo-interactive.sh
# takes: TODO_ID, TODO_TEXT, DAILY_PATH, TODO_LIST_PATH
# returns: 0 on success, 1 on error; prints messages to stdout
run_export() {
    local TODO_ID="$1"
    local TODO_TEXT="$2"
    local DAILY_PATH="$3"
    local TODO_LIST_PATH="$4"
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

    # find ## TODO section and insert before the separator/next heading
    local INSERT_LINE
    INSERT_LINE=$(awk '
        /^## TODO/ { found=1; next }
        found && (/^---/ || /^## /) { print NR; found=0; exit }
        END { if (found) print NR+1 }
    ' "$DAILY_PATH")

    if [[ -z "$INSERT_LINE" ]]; then
        echo "No ## TODO section found in daily note"
        return 1
    fi

    # skip trailing blank lines above separator
    local TOTAL_LINES
    TOTAL_LINES=$(wc -l < "$DAILY_PATH" | tr -d ' ')
    while [[ $INSERT_LINE -gt 1 && $INSERT_LINE -le $TOTAL_LINES ]] && awk -v n="$((INSERT_LINE - 1))" 'NR==n { exit ($0 ~ /^[[:space:]]*$/ ? 0 : 1) }' "$DAILY_PATH"; do
        INSERT_LINE=$((INSERT_LINE - 1))
    done

    # insert using head/tail to avoid sed escaping issues
    {
        head -n "$((INSERT_LINE - 1))" "$DAILY_PATH"
        printf '%s\n' "$NEW_LINE"
        tail -n +"$INSERT_LINE" "$DAILY_PATH"
    } > "${DAILY_PATH}.tmp" && mv "${DAILY_PATH}.tmp" "$DAILY_PATH"

    # set obsidian_ref on the todo
    jq --arg id "$TODO_ID" --arg date "$TODAY" --arg file "$DAILY_PATH" --argjson lnum "$INSERT_LINE" '
        .todos |= map(
            if .id == $id then
                .obsidian_ref = { file: $file, date: $date, lnum: $lnum }
            else . end
        ) |
        ._metadata.updated_at = (now | floor)
    ' "$TODO_LIST_PATH" > "${TODO_LIST_PATH}.tmp" && mv "${TODO_LIST_PATH}.tmp" "$TODO_LIST_PATH"

    echo "Sent to daily: $TODO_TEXT"
    return 0
}

# -- awk section finder tests --

describe "awk: find ## TODO section insert point"

it "finds insert point before --- separator"
DAILY="$TEST_TMPDIR/awk_sep.md"
make_daily_note "$DAILY"
INSERT=$(awk '
    /^## TODO/ { found=1; next }
    found && (/^---/ || /^## /) { print NR; found=0; exit }
    END { if (found) print NR+1 }
' "$DAILY")
# fixture: line 9 is --- (blank lines on 2,5,8,10 push it down)
assert_eq "9" "$INSERT" "should find --- on line 9"

it "finds insert point before next ## heading"
DAILY="$TEST_TMPDIR/awk_heading.md"
make_daily_note_next_heading "$DAILY"
INSERT=$(awk '
    /^## TODO/ { found=1; next }
    found && (/^---/ || /^## /) { print NR; found=0; exit }
    END { if (found) print NR+1 }
' "$DAILY")
# fixture: ## Notes is on line 6 (blank line on 5 pushes it)
assert_eq "6" "$INSERT" "should find ## Notes on line 6"

it "returns end+1 when no terminator after ## TODO"
DAILY="$TEST_TMPDIR/awk_noterm.md"
make_daily_note_no_separator "$DAILY"
INSERT=$(awk '
    /^## TODO/ { found=1; next }
    found && (/^---/ || /^## /) { print NR; found=0; exit }
    END { if (found) print NR+1 }
' "$DAILY")
EXPECTED=$(($(wc -l < "$DAILY" | tr -d ' ') + 1))
assert_eq "$EXPECTED" "$INSERT" "should be last line + 1"

it "returns empty when no ## TODO section"
DAILY="$TEST_TMPDIR/awk_none.md"
cat > "$DAILY" <<'EOF'
# Just a note
some text
EOF
INSERT=$(awk '
    /^## TODO/ { found=1; next }
    found && (/^---/ || /^## /) { print NR; found=0; exit }
    END { if (found) print NR+1 }
' "$DAILY")
assert_eq "" "$INSERT" "should be empty when no TODO section"

it "returns single value (no multi-line output)"
DAILY="$TEST_TMPDIR/awk_single.md"
make_daily_note "$DAILY"
INSERT=$(awk '
    /^## TODO/ { found=1; next }
    found && (/^---/ || /^## /) { print NR; found=0; exit }
    END { if (found) print NR+1 }
' "$DAILY")
LINE_COUNT=$(echo "$INSERT" | wc -l | tr -d ' ')
assert_eq "1" "$LINE_COUNT" "awk should output exactly one line"

# -- full export tests --

describe "obsidian export: basic flow"

it "inserts todo into daily note before ---"
DAILY="$TEST_TMPDIR/export_basic.md"
TODOLIST="$TEST_TMPDIR/export_basic.json"
make_daily_note "$DAILY"
make_todo_list "$TODOLIST" "abc123" "test sync"
run_export "abc123" "test sync" "$DAILY" "$TODOLIST" > /dev/null
assert_file_contains "$DAILY" "- [ ] - test sync <!-- doit:abc123 -->"

it "inserts after existing todos, before separator"
DAILY="$TEST_TMPDIR/export_order.md"
TODOLIST="$TEST_TMPDIR/export_order.json"
make_daily_note "$DAILY"
make_todo_list "$TODOLIST" "abc123" "new todo"
run_export "abc123" "new todo" "$DAILY" "$TODOLIST" > /dev/null
# existing task should still be there
assert_file_contains "$DAILY" "- [ ] - existing task"
# new todo should appear
assert_file_contains "$DAILY" "- [ ] - new todo <!-- doit:abc123 -->"
# separator should still be there
assert_file_contains "$DAILY" "---"

it "sets obsidian_ref on the todo json"
DAILY="$TEST_TMPDIR/export_ref.md"
TODOLIST="$TEST_TMPDIR/export_ref.json"
make_daily_note "$DAILY"
make_todo_list "$TODOLIST" "ref123" "check ref"
run_export "ref123" "check ref" "$DAILY" "$TODOLIST" > /dev/null
REF_DATE=$(jq -r '.todos[0].obsidian_ref.date' "$TODOLIST")
assert_eq "2026-02-22" "$REF_DATE" "obsidian_ref.date should be today"

it "obsidian_ref.lnum is a number not a string"
DAILY="$TEST_TMPDIR/export_lnum.md"
TODOLIST="$TEST_TMPDIR/export_lnum.json"
make_daily_note "$DAILY"
make_todo_list "$TODOLIST" "lnum123" "check lnum"
run_export "lnum123" "check lnum" "$DAILY" "$TODOLIST" > /dev/null
LNUM_TYPE=$(jq -r '.todos[0].obsidian_ref.lnum | type' "$TODOLIST")
assert_eq "number" "$LNUM_TYPE" "lnum should be a number"

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

# -- done --

report
