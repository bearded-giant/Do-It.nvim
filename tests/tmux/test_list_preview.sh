#!/bin/bash

# tests for the list-manager / list-switch fzf previews. Runs preview_list the way
# fzf does — exported into a fresh bash — so an unexported helper in the body fails
# here instead of printing "command not found" in the preview pane.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_harness.sh"

SCRIPTS="$SCRIPT_DIR/../../tmux/scripts"
LONG_TEXT="2. Bring up round-1 stack: monolith preprod (AUTH_SHADOW on) plus the auth service and verify tokens"

cat > "$TEST_TMPDIR/wide.json" <<EOF
{"todos":[
 {"id":"1","text":"$LONG_TEXT","done":false,"in_progress":false,"order_index":1},
 {"id":"2","text":"finished item","done":true,"order_index":2}
]}
EOF

# extract preview_list and run it in a fresh bash, as fzf's --preview does
run_preview() {
    local script="$1" cols="$2"
    sed -n '/^preview_list() {/,/^}/p' "$SCRIPTS/$script" > "$TEST_TMPDIR/fn.sh"
    LISTS_DIR="$TEST_TMPDIR" SHOW_COMPLETED=true FZF_PREVIEW_COLUMNS="$cols" \
        bash -c "source '$TEST_TMPDIR/fn.sh'; export -f preview_list; bash -c 'preview_list wide'" 2>&1
}

for script in todo-list-manager.sh todo-list-switch.sh; do
    describe "$script preview"

    OUT=$(run_preview "$script" 140)

    it "runs with no missing commands in the preview subshell"
    assert_eq "0" "$(grep -c 'command not found' <<< "$OUT")"

    it "lists pending items"
    assert_contains "$OUT" "Bring up round-1 stack"

    it "shows the full item text when the pane is wide"
    assert_contains "$OUT" "$LONG_TEXT"

    it "truncates to the pane width when the pane is narrow"
    NARROW=$(run_preview "$script" 60)
    assert_eq "0" "$(grep -c 'verify tokens' <<< "$NARROW")"

    it "still shows the start of the item when narrow"
    assert_contains "$NARROW" "Bring up round-1"

    it "falls back to a usable width when fzf exports no pane size"
    assert_contains "$(run_preview "$script" "")" "$LONG_TEXT"
done

report
