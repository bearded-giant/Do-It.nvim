#!/bin/bash

# the tmux tag picker lists tags from active items; all-digit tokens such as the
# rank refs in "owed in daily #73" or "(dep on #12)" are not tags.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_harness.sh"

SCRIPTS="$SCRIPT_DIR/../../tmux/scripts"
TODO_LIST_PATH="$TEST_TMPDIR/tags.json"
cat > "$TODO_LIST_PATH" <<'JSON'
{"todos":[
  {"id":"A","text":"[gate] 1. owed in daily #73: merge it #ops (dep on #12)","done":false},
  {"id":"B","text":"deploy #ops #api/v2","done":false}
],"_metadata":{}}
JSON

# fake fzf hands back everything it was offered, so the picker's input is visible
FAKE_BIN="$TEST_TMPDIR/bin"
mkdir -p "$FAKE_BIN"
printf '#!/bin/bash\ncat\n' > "$FAKE_BIN/fzf"
chmod +x "$FAKE_BIN/fzf"
eval "$(sed -n '/^pick_tag() {/,/^}/p' "$SCRIPTS/todo-interactive.sh")"

describe "pick_tag"

it "offers real tags only, most used first"
assert_eq $'ops\napi/v2' "$(PATH="$FAKE_BIN:$PATH" pick_tag)"

report
