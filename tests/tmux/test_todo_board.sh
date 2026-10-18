#!/bin/bash

# board: claude panes (those with @claude_state) on top with the tmux strip's
# glyphs, each on its own list (@doit-pane-list, else the window link, else
# daily); every list below in ACTIVE / OPEN / EMPTY groups, daily first, OPEN
# lists sharing a first dash segment folded. Lines are never cut; the screen is
# a scrolled viewport. A real tmux server on a private socket plays the user's.

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

# mklist name [text active prio]...: one item per triple
mklist() {
    local name=$1
    shift
    local items="[]" i=0
    while (($#)); do
        items=$(jq -c --arg t "$1" --argjson a "$2" --arg p "$3" --argjson i "$i" \
            '. + [{id: "t\($i)", text: $t, done: false, in_progress: $a, order_index: $i, priorities: (if $p == "" then null else $p end)}]' <<< "$items")
        shift 3
        i=$((i + 1))
    done
    jq -n --argjson t "$items" '{todos: $t, _metadata: {}}' > "$DATA/lists/$name.json"
}

# the pty ends lines in \r\n; each redraw starts at \e[H, marked so the last frame can be cut out
strip() { perl -pe 's/\e\[H/\n\@\@FRAME\n/g; s/\e\[[0-9;?]*[a-zA-Z]//g; s/\e\][^\a]*\a//g; s/\r//g'; }
# run through the shebang: /bin/bash on macOS is 3.2, which is what wezterm and tmux run
board_raw() { env -u TMUX_PANE TMUX="$TM" "$SCRIPTS/todo-board.sh" --once; }
board() { board_raw | strip; }
pane() { T display -p -t "$1" '#{pane_id}'; }
claude_rows() { board | sed -n '/^CLAUDE$/,/^LISTS/p'; }
section() { sed -n "/^$1 /,/^[A-Z]/p" | sed '1d;$d'; }

LONG="claude: [spike] 9. $(printf 'word%.0s ' {1..40})end"

mklist daily "my own thing" true ""
describe "todo board"

it "no claude panes: says so, lists still shown"
out=$(board)
assert_contains "$out" " no claude panes"
assert_contains "$out" "ACTIVE 1"

mklist solo-list "claude: [bug] 4. fix the redirect" true critical
mklist left-list "left item" true ""
mklist right-list "idle item" false ""
mklist win-list "window item" true ""
mklist multi "first thing" false "" "second thing" true urgent "third thing" false ""
mklist empty
mklist long-list "$LONG" true ""
mklist grp-a "a one" false "" "a two" false ""
mklist grp-b "b one" false ""

SOLO=$(pane s:solo)
PAIR_A=$(pane s:pair.0)
PAIR_B=$(pane s:pair.1)
BARE=$(pane s:bare)
T set -pq -t "$SOLO" @claude_state busy
T set -pq -t "$SOLO" @claude_state_at "$(date +%s)"
T set -pq -t "$SOLO" @claude_ctx 25
T set -pq -t "$SOLO" @doit-pane-list solo-list
T set -pq -t "$PAIR_A" @claude_state ask
T set -pq -t "$PAIR_A" @claude_state_at "$(($(date +%s) - 420))"
T set -pq -t "$PAIR_A" @doit-pane-list left-list
T set -pq -t "$PAIR_B" @claude_state ready
T set -pq -t "$PAIR_B" @doit-pane-list right-list
T set -wq -t s:pair @doit-window-list win-list
T set -pq -t "$BARE" @claude_state busy
T set -pq -t "$BARE" @claude_err "api error"
out=$(board)
claude=$(claude_rows)
lists=$(printf '%s\n' "$out" | sed -n '/^LISTS/,$p')

it "busy pane: yellow dot, low context, its list and whole active item on one line"
assert_contains "$claude" "●◔25 solo  solo-list  ▸ [bug] 4. fix the redirect"

it "ask pane past 5m shows its age, ready pane off screen shows a check"
assert_contains "$claude" "● pair $PAIR_A 7m  left-list  ▸ left item"
assert_contains "$claude" "✓ pair $PAIR_B  right-list  no active"

it "api error shows ! and the row gets the attention background"
assert_contains "$claude" "! bare  daily  ▸ my own thing"
assert_contains "$(board_raw | grep 'bare')" $'\e[48;5;52;97'

it "pane list wins over the window link"
assert_eq "0" "$(printf '%s\n' "$claude" | grep -c 'win-list')"

it "non-claude window is not a claude row"
assert_eq "0" "$(printf '%s\n' "$claude" | grep -c 'plain')"

it "ACTIVE holds lists with an in-progress item, daily first, the rest by name"
names=$(printf '%s\n' "$lists" | section ACTIVE | grep -v '^     ' | sed -E 's/^.* ([^ ]+) +[0-9]+$/\1/')
assert_eq "daily left-list long-list multi solo-list win-list" "$(echo $names)"

it "OPEN holds idle lists; lists sharing a first segment fold into one row"
open=$(printf '%s\n' "$lists" | section OPEN)
assert_contains "$open" "+ grp-* (2)"
assert_contains "$open" "  ✓ right-list"
assert_eq "0" "$(printf '%s\n' "$open" | grep -c 'grp-a')"

it "EMPTY lists collapse into one line"
assert_contains "$lists" "EMPTY 1  empty"

it "counts sit in one right-aligned column"
assert_eq "1" "$(printf '%s\n' "$lists" | grep -E '^(\+ |- |  [^ ])' | jq -R length | sort -u | wc -l | tr -d ' ')"

it "claude glyphs of panes working a list show before its name"
assert_contains "$lists" "  ● left-list"

it "window links stay hidden until the row is selected"
assert_eq "0" "$(printf '%s\n' "$lists" | grep -c '←')"

it "active item sits under its list"
assert_eq "     ▸ left item" "$(printf '%s\n' "$lists" | grep -A1 '● left-list' | tail -1)"

it "long items are never cut"
assert_contains "$lists" "     ▸ ${LONG#claude: }"

it "filter by list name"
f=$(DOIT_BOARD_FILTER=right board | sed -n '/^LISTS/,$p')
assert_contains "$f" "LISTS  /right"
assert_contains "$f" "right-list"
assert_eq "0" "$(printf '%s\n' "$f" | grep -c 'solo-list')"

it "filter by item text shows only the matching items"
f=$(DOIT_BOARD_FILTER=THIRD board | sed -n '/^LISTS/,$p')
assert_contains "$f" "     · third thing"
assert_eq "0" "$(printf '%s\n' "$f" | grep -c 'first thing')"

it "a filter shows folded lists flat"
f=$(DOIT_BOARD_FILTER=grp board | sed -n '/^LISTS/,$p')
assert_contains "$f" "  grp-a"
assert_eq "0" "$(printf '%s\n' "$f" | grep -c 'grp-\*')"

it "a filter with no hits says so"
assert_contains "$(DOIT_BOARD_FILTER=zzz board)" "  no match"

it "unstamped pane falls back to the window link"
T set -pqu -t "$PAIR_A" @doit-pane-list
assert_contains "$(claude_rows)" "pair $PAIR_A 7m  win-list"
T set -pq -t "$PAIR_A" @doit-pane-list left-list

describe "todo board input"

# one fake client; switch-client is recorded instead of run, the rest hits the private server
FAKE_BIN="$TEST_TMPDIR/fakebin"
SWITCHED="$TEST_TMPDIR/switched"
SCREEN="$TEST_TMPDIR/screen"
mkdir -p "$FAKE_BIN"
cat > "$FAKE_BIN/tmux" << EOF
#!/bin/bash
case "\$1" in
    list-clients) [[ "\$3" == *client_activity* ]] && printf '5\x1f/dev/ttyfake\n' || echo /dev/ttyfake ;;
    switch-client) echo "\$*" >> "$SWITCHED" ;;
    *) exec "$(command -v tmux)" -S "$SOCK" "\$@" ;;
esac
EOF
chmod +x "$FAKE_BIN/tmux"

# drive [LINES COLUMNS] keys...: keys go in through a pty one chunk at a time
# (PAUSE idles past a redraw tick), then q; prints the switch-client calls, the
# stripped screen lands in $SCREEN
drive() {
    local lines=60 cols=200
    if [[ "$1" =~ ^[0-9]+$ ]]; then
        lines=$1 cols=$2
        shift 2
    fi
    : > "$SWITCHED"
    (
        sleep 1
        for k in "$@"; do
            if [[ "$k" == PAUSE ]]; then
                sleep 2.5
                continue
            fi
            printf "$k"
            sleep 0.4
        done
        printf q
    ) | env -u TMUX_PANE -u WEZTERM_PANE TMUX="$TM" PATH="$FAKE_BIN:$PATH" COLUMNS="$cols" LINES="$lines" \
        DOIT_BOARD_INTERVAL=1 perl -e 'alarm 30; exec @ARGV' script -q /dev/null "$SCRIPTS/todo-board.sh" 2> /dev/null |
        tee "$SCREEN.raw" | strip > "$SCREEN"
    cat "$SWITCHED"
}

# last non-empty frame drawn (the exit clears the screen with one more)
last_frame() {
    awk '/^@@FRAME$/ { if (buf != "") last = buf; buf = ""; next } { buf = buf $0 "\n" } END { if (buf != "") last = buf; printf "%s", last }' "$SCREEN"
}
row_of() { board | grep -n -- "$1" | head -1 | cut -d: -f1; }

# screen rows: 1 CLAUDE, 2 session, 3 solo, 4 pair A, 5 pair B, 6 bare
it "j then enter jumps the client to the first claude pane"
assert_eq "switch-client -c /dev/ttyfake -t $SOLO" "$(drive j '\r')"

it "arrow down twice then enter jumps to the second pane"
assert_eq "switch-client -c /dev/ttyfake -t $PAIR_A" "$(drive '\e[B' '\e[B' '\r')"

it "click on a claude row jumps to its pane"
assert_eq "switch-client -c /dev/ttyfake -t $PAIR_A" "$(drive '\e[<0;5;4M' '\e[<0;5;4m')"

it "click on a header does nothing"
assert_eq "" "$(drive '\e[<0;2;1M')"

it "enter with nothing selected does nothing"
assert_eq "" "$(drive '\r')"

it "nothing selected: no row is highlighted"
assert_eq "0" "$(grep -c $'\e\\[7' "$SCREEN.raw")"

it "idle redraw ticks do not end the board"
assert_eq "switch-client -c /dev/ttyfake -t $SOLO" "$(drive PAUSE j '\r')"

it "click on a list opens every open item, priority first, without jumping"
assert_eq "" "$(drive "\e[<0;3;$(row_of '  multi ')M")"
assert_contains "$(last_frame | grep -A3 '  multi ' | tail -3 | tr '\n' '|')" "     ▸ second thing|     · first thing|     · third thing|"

it "click on a fold opens its lists"
drive "\e[<0;3;$(row_of '+ grp-')M" > /dev/null
assert_contains "$(last_frame)" "- grp-* (2)"
assert_contains "$(last_frame)" "    grp-a"

it "selected list shows its window links"
drive "\e[<0;3;$(row_of '  win-list ')M" > /dev/null
assert_contains "$(last_frame)" "← s:pair"

it "/ filters as you type and keys are text while typing"
drive / r i q > /dev/null
f=$(last_frame | sed -n '/^LISTS/,$p')
assert_contains "$f" "LISTS  /riq"
assert_contains "$f" "  no match"

it "enter keeps the filter, esc clears it"
drive / r i g h t '\r' > /dev/null
f=$(last_frame | sed -n '/^LISTS/,$p')
assert_contains "$f" "LISTS  /right  esc clears"
assert_eq "0" "$(printf '%s\n' "$f" | grep -c 'solo-list')"
drive / x y '\r' '\e' PAUSE > /dev/null
assert_contains "$(last_frame)" "LISTS  / filter"

it "a opens every list and fold"
drive a > /dev/null
assert_contains "$(last_frame)" "     · idle item"
assert_contains "$(last_frame)" "    grp-b"

it "right arrow scrolls sideways instead of cutting"
drive 60 30 '\e[C' > /dev/null
assert_contains "$(grep -c '^olo  solo-list  ▸ \[bug\] 4. fix$' "$SCREEN")" "1"

it "wheel scrolls down, footer shows the window into the board"
drive 6 200 '\e[<65;5;3M' > /dev/null
assert_contains "$(cat "$SCREEN")" " 1-5/"
assert_contains "$(cat "$SCREEN")" " 4-8/"

report
