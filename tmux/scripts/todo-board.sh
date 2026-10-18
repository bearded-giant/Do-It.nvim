#!/bin/bash

# Always-on board of every claude pane for a split beside tmux (the wezterm
# toggle runs it); --once prints one frame. q quits.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/get-active-list.sh"

# integer: bash 3.2 read -t takes no fractions
INTERVAL="${DOIT_BOARD_INTERVAL:-2}"

FMT="#{session_name}${DOIT_SEP}#{window_name}${DOIT_SEP}#{pane_id}${DOIT_SEP}#{@claude_state}${DOIT_SEP}#{@doit-pane-list}${DOIT_SEP}#{@doit-window-list}${DOIT_SEP}#{&&:#{session_attached},#{window_active}}${DOIT_SEP}#{pane_dead}${DOIT_SEP}#{session_attached}"

# jq does the layout: it cuts by character, bash 3.2 cuts multibyte text mid-glyph
read -r -d '' RENDER << 'JQ'
def esc($c): "\u001b[\($c)m";
def fit($n): if length > $n then .[0:([$n - 1, 0] | max)] + "…" else . end;
(reduce inputs as $l ({}; . + {(input_filename | split("/") | last | rtrimstr(".json")): $l})) as $lists
| def todos($name): ($lists[$name].todos // []);
  def item($name; $w):
    ([todos($name)[] | select(.in_progress == true)][0]) as $a
    | if $a == null then
        esc("2") + ("no active · \([todos($name)[] | select(.done | not)] | length) open" | fit($w)) + esc("0")
      else
        ({critical: "31", urgent: "33", important: "36"}[$a.priorities // ""] // "0") as $c
        | esc($c) + ("▸ " + ($a.text | gsub("\\s+"; " ") | sub("^ "; "") | ltrimstr("claude: ")) | fit($w)) + esc("0")
      end;
  ($panes | split("\n") | map(select(length > 0) | split($sep)
    | {s: .[0], w: .[1], p: .[2], st: .[3], focus: (.[6] == "1"), dead: (.[7] == "1"), att: (.[8] == "1"),
       list: (if .[4] != "" then .[4] elif .[5] != "" then .[5] else "daily" end)})
    | map(select(.st != ""))) as $rows
  | (if $rows == [] then [esc("2") + "no claude panes" + esc("0")]
     else [$rows | group_by(.s)[] as $g
       | (if $g[0].att then esc("1") else esc("2") end) + ($g[0].s | fit($cols)) + esc("0"),
         ($g[] as $r
          | ([$g[] | select(.w == $r.w)] | length > 1) as $shared
          | (if $r.focus then esc("1;34") + "▌" else " " end)
            + (if $r.dead then esc("90") + "×" else esc({ask: "31", busy: "33", ready: "32"}[$r.st] // "90") + "●" end)
            + esc("0") + " " + (if $r.focus then esc("1") else "" end)
            + (($r.w + (if $shared then " " + $r.p else "" end)) | fit($cols - 3)) + esc("0"),
            "   " + esc("2") + ($r.list | fit($cols - 3)) + esc("0"),
            "   " + item($r.list; $cols - 3))]
     end)
    + ["", esc("1") + "daily" + esc("0"), "   " + item("daily"; $cols - 3)]
  | map(. + "\u001b[K") | join("\n")
JQ

render() {
    local panes names=" daily " files=() state plist wlist n
    panes=$(tmux list-panes -a -F "$FMT" 2>/dev/null)
    while IFS="$DOIT_SEP" read -r _ _ _ state plist wlist _; do
        [[ -n "$state" ]] || continue
        n=${plist:-${wlist:-daily}}
        [[ "$names" == *" $n "* ]] || names="$names$n "
    done <<< "$panes"
    for n in $names; do
        [[ -f "$LISTS_DIR/$n.json" ]] && files+=("$LISTS_DIR/$n.json")
    done
    # /dev/null keeps jq off stdin when no list file exists
    jq -rn --arg panes "$panes" --arg sep "$DOIT_SEP" --argjson cols "$(tput cols 2>/dev/null || echo 40)" \
        "$RENDER" "${files[@]}" /dev/null
}

if [[ "$1" == "--once" ]]; then
    render
    exit
fi

# wezterm finds this pane by the user var to toggle it
printf '\e]1337;SetUserVar=doit_board=MQ==\a'
tput civis 2>/dev/null
trap 'tput cnorm 2>/dev/null; printf "\e[2J\e[H"' EXIT
trap 'last=' WINCH
last=""
while :; do
    out=$(render | head -n "$(tput lines 2>/dev/null || echo 50)")
    if [[ "$out" != "$last" ]]; then
        printf '\e[H%s\e[J' "$out"
        last=$out
    fi
    read -rsn1 -t "$INTERVAL" key && [[ "$key" == q ]] && exit 0
done
