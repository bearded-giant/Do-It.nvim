#!/bin/bash

# Always-on board for a split beside tmux (the wezterm toggle runs it): claude
# panes with their tmux status glyphs on top, every list below grouped ACTIVE /
# OPEN / EMPTY. Rows are never cut; the screen is a viewport you scroll.
# --once prints the whole board.
#
# up/down j/k select   enter/click: jump to pane, open list or group   a: open all
# / filter (enter keeps it, esc clears)   left/right h/l scroll sideways
# wheel, ctrl-d/u, g/G scroll   q quit

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/get-active-list.sh"
shopt -s nullglob

# integer: bash 3.2 read -t takes no fractions
INTERVAL="${DOIT_BOARD_INTERVAL:-2}"

S="$DOIT_SEP"
FMT="#{session_name}$S#{window_name}$S#{pane_id}$S#{@claude_state}$S#{@doit-pane-list}$S#{@doit-window-list}$S#{&&:#{session_attached},#{window_active}}$S#{pane_dead}$S#{session_attached}$S#{@claude_state_at}$S#{@claude_err}$S#{@claude_attention}$S#{@claude_attention_ack}$S#{@claude_ctx}"

# jq owns layout because it counts characters; bash 3.2 slices multibyte text mid-glyph.
# A line is {k, segs: [[sgr, text]...], trail}; k ("P:<pane>" / "L:<list>" / "F:<prefix>")
# is what a click on it acts on, trail shows only while the line is selected.
# Stick to jq 1.7 syntax: wezterm's login shell finds macOS /usr/bin/jq first.
read -r -d '' RENDER << 'JQ'
def esc($c): "\u001b[\($c)m";
def width: map(.[1] | length) | add // 0;
def spaces($n): [range([$n, 0] | max)] | map(" ") | add // "";
def pos($x): (to_entries | map(select(.value == $x)) | .[0].key) // -1;
def clean: gsub("\\s+"; " ") | sub("^ "; "") | ltrimstr("claude: ");
def prio: {critical: "31", urgent: "33", important: "36"}[.priorities // ""] // "";
def rank: if .priorities == "critical" then 0 elif .priorities == "urgent" then 1 elif .priorities == "important" then 2 else 3 end;
def order: sort_by((if (.sequence | type) == "number" then [0, .sequence] else [1, 0] end), rank, .order_index);
def sgr($a; $b): [$a, $b] | map(select(. != "")) | join(";");
def secs: now - (.at | tonumber? // now);
# mirrors @claude_glyph / @claude_needs / @claude_age in the tmux claude strip
def needs: .err != "" or .unacked or .st == "ask";
def age: (secs / 60 | floor) as $m | if $m >= 60 then "\($m / 60 | floor)h" elif $m >= 1 then "\($m)m" else "" end;
def glyph:
  (if .dead then [["90", "×"]]
   elif .err != "" then [["31", "!"]]
   elif .unacked or .st == "ask" then [[(if secs > 300 then "1;31" else "31" end), "●"]]
   elif .st == "busy" then (if secs > 600 then [["33", "?"]] else [["33", "●"]] end)
   elif .focus then [["32", "●"]]
   else [["32", "✓"]] end)
  + ((.ctx | tonumber? // 100) as $c | if $c < 30 then [[(if $c < 20 then "31" else "38;5;208" end), "◔\(.ctx)"]] else [] end);
def slice($off; $w):
  reduce .[] as $s ({pos: 0, out: []};
    ($s[1] | length) as $n
    | ([$off - .pos, 0] | max) as $a
    | ([$off + $w - .pos, $n] | min) as $b
    | (if $b > $a then .out += [[$s[0], $s[1][$a:$b]]] else . end)
    | .pos += $n)
  | .out;
def draw: map(esc(.[0]) + .[1] + esc("0")) | add // "";
# shared leading dash segments: merchant-mcp-a, merchant-mcp-b -> merchant-mcp
def lcp:
  map(split("-")) as $p
  | reduce range(0; $p | map(length) | min) as $i ([];
      if length == $i and ([$p[][$i]] | unique | length) == 1 then . + [$p[0][$i]] else . end)
  | join("-");

(reduce inputs as $l ({}; . + {(input_filename | split("/") | last | rtrimstr(".json")): $l})) as $lists
| ($panes | split("\n") | map(select(length > 0) | split($sep)
    | {s: .[0], w: .[1], p: .[2], st: .[3], plist: .[4], wlist: .[5], focus: (.[6] == "1"), dead: (.[7] == "1"),
       att: (.[8] == "1"), at: .[9], err: .[10], unacked: (.[11] != "" and .[11] != .[12]), ctx: .[13]}
    | .list = (if .plist != "" then .plist elif .wlist != "" then .wlist else "daily" end))) as $all
| ($all | map(select(.st != ""))) as $claude
| ($all | map(select(.wlist != "")) | group_by(.wlist) | map({key: .[0].wlist, value: (map(.s + ":" + .w) | unique)}) | from_entries) as $links
| ($claude | group_by(.list) | map({key: .[0].list, value: .}) | from_entries) as $onlist
| ($filter | ascii_downcase) as $f
| def active($n): ($lists[$n].todos // []) | map(select(.in_progress == true and (.done | not))) | .[0];
  def expanded($k): ($expanded | any(.[]; . == "*")) != ($expanded | any(.[]; . == $k));
  def item($k; $ind):
    {k: $k, segs: [[sgr(prio; (if .in_progress == true then "1" else "" end)),
      $ind + "   " + (if .in_progress == true then "▸ " else "· " end) + (.text | clean)]]};
  # a block with item lines under it gets a blank row after, for air between blocks
  def listrow($ind):
    . as $r
    | ("L:" + $r.n) as $k
    | [if $r.hits != null then ($r.hits[] | item($k; $ind))
       elif expanded($k) then ($r.open[] | item($k; $ind))
       elif $r.a then ($r.a | item($k; $ind))
       else empty end] as $items
    | {k: $k,
       pre: [["", $ind], [(if $r.a then "1" else "" end), $r.n]],
       count: ($r.open | length),
       trail: (if ($links[$r.n] // []) == [] then [] else [["2", "  ← " + ($links[$r.n] | join(", "))]] end)},
      $items[],
      (if $items == [] then empty else {k: "", segs: []} end);
  # a filter shows matches flat; otherwise lists sharing a first dash segment fold into one row
  def folded:
    if $f != "" then .[] | listrow("  ")
    else group_by(.n | split("-")[0])[] as $g
      | if ($g | length) == 1 then $g[0] | listrow("  ")
        else ($g | map(.n) | lcp) as $p
          | ("F:" + ($g[0].n | split("-")[0])) as $k
          | expanded($k) as $exp
          | {k: $k,
             pre: [["2", (if $exp then "- " else "+ " end)], ["", $p + (if any($g[]; .n == $p) then "*" else "-*" end)],
                   ["2", " (\($g | length))"]],
             count: ($g | map(.open | length) | add)},
            (if $exp then $g[] | listrow("    ") else empty end)
        end
    end;

  ([{k: "", segs: [["1", "CLAUDE"]]}]
   + (if $claude == [] then [{k: "", segs: [["2", " no claude panes"]]}]
      else [$claude | group_by(.s) | to_entries[] as $e | $e.value as $g
        | (if $e.key > 0 then {k: "", segs: []} else empty end),
          {k: "", segs: [[(if $g[0].att then "1" else "2" end), " " + $g[0].s]]},
          ($g[] as $r
           | ([$g[] | select(.w == $r.w)] | length > 1) as $shared
           | active($r.list) as $a
           | ([[(if $r.focus then "1;34" else "" end), (if $r.focus then "▌" else " " end)], ["", " "]]
              + ($r | glyph)
              + [[(if $r.focus then "1" else "" end), " " + $r.w + (if $shared then " " + $r.p else "" end)]]
              + (if ($r | needs) and ($r | age) != "" then [["90", " " + ($r | age)]] else [] end)
              + [["2", "  " + $r.list]]
              + (if $a then [[($a | prio), "  ▸ " + ($a.text | clean)]] else [["2", "  no active"]] end)) as $segs
           | {k: ("P:" + $r.p),
              segs: (if $r | needs then $segs | map([sgr("48;5;52;97"; .[0]), .[1]]) else $segs end)})]
      end)) as $crows

  # a list a claude pane works already has its row up top; daily stays, unstamped panes fall back to it
  | [(["daily"] + ($lists | keys | map(select(. != "daily" and $onlist[.] == null))))[] as $n
     | (($lists[$n].todos // []) | map(select(.done | not)) | order) as $open
     | (if $f == "" or ($n | ascii_downcase | contains($f)) then null
        else [$open[] | select(.text | ascii_downcase | contains($f))] end) as $hits
     | select($hits == null or ($hits | length) > 0)
     | {n: $n, open: $open, a: active($n), hits: $hits}] as $L
  | ($L | map(select(.a != null))) as $act
  | ($L | map(select(.a == null and (.open | length) > 0))) as $opn
  | ($L | map(select(.a == null and (.open | length) == 0))) as $emp
  | ([{k: "", segs: []},
      {k: "", segs: ([["1", "LISTS"]]
         + (if $typing then [["", "  /" + $filter], ["7", " "]]
            elif $filter != "" then [["33", "  /" + $filter], ["2", "  esc clears"]]
            else [["2", "  / filter"]] end))}]
     + (if $L == [] then [{k: "", segs: [["2", "  no match"]]}] else [] end)
     + (if $act == [] then []
        else [{k: "", segs: [["36", "ACTIVE"], ["2", " \($act | length)"]]}] + [$act[] | listrow("  ")] end)
     + (if $opn == [] then []
        else [{k: "", segs: [["36", "OPEN"], ["2", " \($opn | length)"]]}]
          + [($opn | map(select(.n == "daily")))[] | listrow("  ")]
          + [$opn | map(select(.n != "daily")) | folded] end)
     + (if $emp == [] then []
        else [{k: "", segs: [["36", "EMPTY"], ["2", " \($emp | length)  " + ($emp | map(.n) | join("  "))]]}] end)
     | if .[-1] == {k: "", segs: []} then .[:-1] else . end) as $lrows
  # counts right-aligned in one column so names scan as a list
  | ($lrows | map(select(.pre) | .pre | width) | max // 0) as $w
  | ($lrows | map(select(.pre) | .count | tostring | length) | max // 0) as $cw
  | ($crows + ($lrows | map(if .pre then
        {k, trail, segs: (.pre + [["", spaces($w + 2 - (.pre | width) + $cw - (.count | tostring | length))],
                                  [(if .count == 0 then "2" else "" end), (.count | tostring)]])}
      else . end))) as $c

  | if $once then $c[] | .segs | draw
    else
      ($c | map(.k) | reduce .[] as $k ([]; if $k != "" and (any(.[]; . == $k) | not) then . + [$k] else . end)) as $keys
      | ($keys | length) as $nk
      | (if $nk == 0 then ""
         elif $move == 0 then (if ($keys | pos($sel)) >= 0 then $sel else "" end)
         else ($keys | pos($sel)) as $i
           | $keys[if $i < 0 then (if $move > 0 then 0 else $nk - 1 end) else ((($i + $move) % $nk) + $nk) % $nk end]
         end) as $nsel
      | (if $nsel == "" then -1 else $c | map(.k) | pos($nsel) end) as $line
      | ([$rows - 1, 1] | max) as $body
      | ($c | length) as $total
      | (if $follow and $line >= 0 then
           (if $line < $row_off then $line elif $line >= $row_off + $body then $line - $body + 1 else $row_off end)
         else $row_off end) as $ro
      | ([[$ro, $total - $body] | min, 0] | max) as $ro
      | ($c | map(.segs | width) | max // 0) as $maxw
      | ([[$col_off, $maxw - $cols] | min, 0] | max) as $co
      | ([$nsel, $ro, $co] | join($sep)),
        ($c[$ro:$ro + $body] | to_entries[]
         | (.key + $ro == $line) as $hit
         | .value.k + $sep
           + (.value.segs + (if $hit then .value.trail // [] else [] end) | slice($co; $cols)
              | if $hit then map([sgr("7"; .[0]), .[1]]) + [["7", spaces($cols - width)]] else . end
              | draw)
           + "\u001b[K"),
        ($sep + esc("2") + (" \($ro + 1)-\([$ro + $body, $total] | min)/\($total)  ↔ \($co)/\([$maxw - $cols, 0] | max)" | .[0:$cols]) + esc("0") + "\u001b[K")
    end
JQ

SEL=""
MOVE=0
FOLLOW=false
ROW_OFF=0
COL_OFF=0
EXPANDED="[]"
FILTER=""
TYPING=false
ROWS=50
COLS=40

render() {
    local once=${1:-false}
    jq -rn --arg panes "$(tmux list-panes -a -F "$FMT" 2>/dev/null)" --arg sep "$S" --arg sel "$SEL" \
        --argjson move "$MOVE" --argjson follow "$FOLLOW" --argjson row_off "$ROW_OFF" --argjson col_off "$COL_OFF" \
        --argjson rows "$ROWS" --argjson cols "$COLS" --argjson expanded "$EXPANDED" --argjson once "$once" \
        --arg filter "$FILTER" --argjson typing "$TYPING" \
        "$RENDER" "$LISTS_DIR"/*.json /dev/null
}

if [[ "$1" == "--once" ]]; then
    FILTER="${DOIT_BOARD_FILTER:-}"
    render true
    exit
fi

# the input loop needs a terminal: off one, a read failing at EOF would spin
[[ -t 0 ]] || {
    echo "todo-board: stdin is not a terminal (use --once)" >&2
    exit 1
}

read_size() {
    local r c
    read -r r c < <(stty size < /dev/tty 2>/dev/null)
    if ((c > 0)); then
        ROWS=$r COLS=$c
    else
        ROWS=${LINES:-50} COLS=${COLUMNS:-40}
    fi
}

# LINE_TARGET maps screen row -> what a click there acts on
draw() {
    local line meta i=0 frame=""
    read_size
    LINE_TARGET=()
    {
        IFS= read -r meta
        IFS="$S" read -r SEL ROW_OFF COL_OFF <<< "$meta"
        while IFS= read -r line; do
            LINE_TARGET[i]=${line%%"$S"*}
            frame+="${line#*"$S"}"$'\n'
            i=$((i + 1))
        done
    } <<< "$(render)"
    MOVE=0
    FOLLOW=false
    frame=${frame%$'\n'}
    if [[ "$frame" != "$last" ]]; then
        printf '\e[H%s\e[J' "$frame"
        last=$frame
    fi
}

toggle() {
    EXPANDED=$(jq -cn --argjson e "$EXPANDED" --arg n "$1" 'if any($e[]; . == $n) then $e - [$n] else $e + [$n] end')
}

clear_filter() {
    FILTER=""
    TYPING=false
    ROW_OFF=0
}

# Switch the tmux client in the pane to our right (the wezterm split) to pane $1,
# then hand focus back to it. Without wezterm, the last active client moves.
jump() {
    local tty="" right=""
    if [[ -n "$WEZTERM_PANE" ]] && command -v wezterm &>/dev/null; then
        right=$(wezterm cli get-pane-direction Right 2>/dev/null)
        [[ -n "$right" ]] && tty=$(wezterm cli list --format json 2>/dev/null |
            jq -r --argjson id "$right" '.[] | select(.pane_id == $id) | .tty_name // empty')
    fi
    tmux list-clients -F '#{client_tty}' 2>/dev/null | grep -qxF -- "$tty" ||
        tty=$(tmux list-clients -F "#{client_activity}$S#{client_tty}" 2>/dev/null |
            sort -rn | head -1 | cut -d "$S" -f2)
    [[ -n "$tty" ]] || return 1
    tmux switch-client -c "$tty" -t "$1" 2>/dev/null
    [[ -n "$right" ]] && wezterm cli activate-pane --pane-id "$right" 2>/dev/null
    return 0
}

act() {
    case "$1" in
        P:*) jump "${1#P:}" ;;
        L:* | F:*) toggle "$1" ;;
    esac
}

# arrows arrive as ESC [ A-D, SGR mouse as ESC [ < button ; col ; row M (press) or m (release);
# a lone ESC (nothing follows within read's 1s floor) clears the filter
read_escape() {
    local c seq="" b x y target
    if ! IFS= read -rsn1 -t 1 c; then
        clear_filter
        return
    fi
    [[ "$c" == "[" || "$c" == "O" ]] || return
    IFS= read -rsn1 -t 1 c || return
    case "$c" in
        A) MOVE=-1 FOLLOW=true ;;
        B) MOVE=1 FOLLOW=true ;;
        C) COL_OFF=$((COL_OFF + 8)) ;;
        D) COL_OFF=$((COL_OFF - 8)) ;;
        "<")
            while IFS= read -rsn1 -t 1 c; do
                [[ "$c" == M || "$c" == m ]] && break
                seq+=$c
            done
            [[ "$c" == M ]] || return
            IFS=';' read -r b x y <<< "$seq"
            case "$b" in
                0)
                    target=${LINE_TARGET[$((y - 1))]}
                    [[ -n "$target" ]] && SEL=$target && act "$target"
                    ;;
                64) ROW_OFF=$((ROW_OFF - 3)) ;;
                65) ROW_OFF=$((ROW_OFF + 3)) ;;
                66) COL_OFF=$((COL_OFF - 8)) ;;
                67) COL_OFF=$((COL_OFF + 8)) ;;
            esac
            ;;
    esac
}

# wezterm finds this pane by the user var to toggle it
printf '\e]1337;SetUserVar=doit_board=MQ==\a'
printf '\e[?1000h\e[?1006h'
tput civis 2>/dev/null
trap 'printf "\e[?1000l\e[?1006l"; tput cnorm 2>/dev/null; printf "\e[2J\e[H"' EXIT
trap 'last=' WINCH
last=""
while :; do
    draw
    # bash 3.2 (macOS /bin/bash) returns 1 on timeout, same as EOF; a closed terminal ends us by SIGHUP
    IFS= read -rsn1 -t "$INTERVAL" key || continue
    if [[ "$TYPING" == true ]]; then
        case "$key" in
            "") TYPING=false ;;
            $'\e') read_escape ;;
            $'\x7f' | $'\b') FILTER=${FILTER%?} ROW_OFF=0 ;;
            *) FILTER+=$key ROW_OFF=0 ;;
        esac
        continue
    fi
    case "$key" in
        q) exit 0 ;;
        /) TYPING=true ;;
        j) MOVE=1 FOLLOW=true ;;
        k) MOVE=-1 FOLLOW=true ;;
        l) COL_OFF=$((COL_OFF + 8)) ;;
        h) COL_OFF=$((COL_OFF - 8)) ;;
        g) ROW_OFF=0 ;;
        G) ROW_OFF=1000000 ;;
        $'\x04') ROW_OFF=$((ROW_OFF + ROWS / 2)) ;;
        $'\x15') ROW_OFF=$((ROW_OFF - ROWS / 2)) ;;
        a) EXPANDED=$(jq -cn --argjson e "$EXPANDED" 'if any($e[]; . == "*") then [] else ["*"] end') ;;
        "") act "$SEL" ;;
        $'\e') read_escape ;;
    esac
done
