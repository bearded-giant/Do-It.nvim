#!/bin/bash

# tests for todo-export.sh: only pending items, priority headers, order, notes.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_harness.sh"

EXPORT_SH="$SCRIPT_DIR/../../tmux/scripts/todo-export.sh"
FIXTURE="$TEST_TMPDIR/work.json"
OUT="$TEST_TMPDIR/out.md"

cat > "$FIXTURE" <<'EOF'
{
  "todos": [
    {"id":"1","text":"fix auth bug","done":false,"in_progress":false,"order_index":3,"priorities":"critical","description":"check token expiry\n\nsecond para\n\n\n----------\nlast modified: 2026-07-14: 16:00"},
    {"id":"2","text":"ship release","done":false,"in_progress":true,"order_index":9,"priorities":"critical"},
    {"id":"3","text":"multi\nline item","done":false,"in_progress":false,"order_index":1},
    {"id":"4","text":"already done","done":true,"in_progress":false,"order_index":2,"priorities":"urgent"},
    {"id":"5","text":"footer only note","done":false,"in_progress":false,"order_index":5,"description":"\n\n\n----------\nlast modified: 2026-07-14: 16:00"},
    {"id":"6","text":"nudge docs","done":false,"in_progress":false,"order_index":7,"priorities":"important"}
  ],
  "_metadata": {"name":"work"}
}
EOF

"$EXPORT_SH" "$OUT" "$FIXTURE" > /dev/null
MD=$(cat "$OUT")

describe "todo-export.sh: markdown export"

it "titles the doc with the list name"
assert_file_line "$OUT" 1 "# work"

it "skips completed items"
TESTS_RUN=$((TESTS_RUN + 1))
if grep -qF "already done" "$OUT"; then
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  FAIL: $CURRENT_TEST (completed item leaked into export)"
    FAILURES="${FAILURES}\n  - $CURRENT_TEST: completed item leaked"
else
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "  pass: $CURRENT_TEST"
fi

it "emits a header per non-empty priority"
assert_contains "$MD" "## Critical"
it "emits Important header"
assert_contains "$MD" "## Important"
it "emits Default header"
assert_contains "$MD" "## Default"
it "omits Urgent header (only completed urgent item)"
assert_eq "0" "$(grep -c '^## Urgent$' "$OUT")"

it "puts in-progress first inside its priority section"
assert_eq "- [ ] ship release" "$(grep -n '^- \[ \]' "$OUT" | head -1 | cut -d: -f2-)"

it "keeps section order critical -> important -> default"
assert_eq $'## Critical\n## Important\n## Default' "$(grep '^## ' "$OUT")"

it "indents the note under its item and strips the footer"
assert_contains "$MD" "  check token expiry"
it "preserves blank lines inside the note"
assert_contains "$MD" $'  check token expiry\n\n  second para'
it "drops the machine footer from notes"
assert_eq "0" "$(grep -c 'last modified' "$OUT")"

it "indents continuation lines of multi-line item text"
assert_contains "$MD" $'- [ ] multi\n  line item'

it "emits no note block for a footer-only description"
assert_contains "$MD" $'- [ ] footer only note\n'

it "matches the nvim exporter golden output (see export_markdown_spec.lua)"
GOLDEN=$'# work\n\n_exported STAMP_\n\n## Critical\n\n- [ ] ship release\n\n- [ ] fix auth bug\n\n  check token expiry\n\n  second para\n\n## Important\n\n- [ ] nudge docs\n\n## Default\n\n- [ ] multi\n  line item\n\n- [ ] footer only note'
assert_eq "$GOLDEN" "$(sed 's/^_exported .*_$/_exported STAMP_/' "$OUT")"

it "reports the written path on stdout"
assert_eq "$OUT" "$("$EXPORT_SH" "$OUT" "$FIXTURE")"

it "handles a list with no pending items"
EMPTY="$TEST_TMPDIR/empty.json"
echo '{"todos":[{"id":"1","text":"done","done":true,"order_index":1}]}' > "$EMPTY"
"$EXPORT_SH" "$TEST_TMPDIR/empty.md" "$EMPTY" > /dev/null
assert_file_contains "$TEST_TMPDIR/empty.md" "_no pending items_"

# same fixture and golden as export_markdown_spec.lua "nests children"
it "nests children under their parent (golden shared with the nvim exporter)"
NESTED="$TEST_TMPDIR/nest.json"
cat > "$NESTED" <<'EOF'
{
  "todos": [
    {"id":"p","text":"parent","done":false,"order_index":1},
    {"id":"c2","text":"second child","done":false,"order_index":3,"parent_id":"p"},
    {"id":"c1","text":"first child\nmore","done":false,"order_index":2,"parent_id":"p","description":"child note"},
    {"id":"g","text":"grandchild","done":false,"order_index":4,"parent_id":"c1"},
    {"id":"dp","text":"done parent","done":true,"order_index":5},
    {"id":"oc","text":"orphaned child","done":false,"order_index":6,"parent_id":"dp","priorities":"urgent"},
    {"id":"dc","text":"done child","done":true,"order_index":7,"parent_id":"p"},
    {"id":"u","text":"urgent root","done":false,"order_index":8,"priorities":"urgent"}
  ]
}
EOF
"$EXPORT_SH" "$TEST_TMPDIR/nest.md" "$NESTED" > /dev/null
GOLDEN=$'# nest\n\n_exported STAMP_\n\n## Urgent\n\n- [ ] orphaned child\n\n- [ ] urgent root\n\n## Default\n\n- [ ] parent\n\n  - [ ] first child\n    more\n\n    child note\n\n    - [ ] grandchild\n\n  - [ ] second child'
assert_eq "$GOLDEN" "$(sed 's/^_exported .*_$/_exported STAMP_/' "$TEST_TMPDIR/nest.md")"

report
