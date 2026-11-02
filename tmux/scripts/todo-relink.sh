#!/bin/bash

# Keeps the persisted window links in session.json (keyed "<session>:<window>")
# on the names their windows carry now. The live link is the @doit-window-list window
# option, which already survives renames and moves; the persisted copy is what
# a tmux restart restores from, so it has to follow. doit.tmux runs this from
# the window-renamed, session-renamed and window-linked hooks.
#
# --migrate (plugin load): drops keys without ':', links from when lists bound
# whole sessions. Copying one onto every window of its session put one list's
# todo on unrelated windows, so those windows fall back to daily instead.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/get-active-list.sh"

[[ -n "$TMUX" ]] || exit 0
command -v jq &>/dev/null || exit 0
command -v tmux &>/dev/null || exit 0

windows=$(_doit_tmux list-windows -a -F "#{window_id}${DOIT_SEP}#{@doit-window-list}${DOIT_SEP}#{@doit-window-key}${DOIT_SEP}#{session_name}${DOIT_SEP}#S:#W" 2>/dev/null)
[[ -n "$windows" ]] || exit 0
live_keys=$(printf '%s\n' "$windows" | awk -F"$DOIT_SEP" '{print $5}')

while IFS="$DOIT_SEP" read -r id list stamped sess key; do
    [[ -n "$list" && "$stamped" != "$key" ]] || continue
    # the old name's entry goes only when it is still this window's and no live window took that name
    drop=false
    if [[ -n "$stamped" ]] && ! grep -qxF -- "$stamped" <<< "$live_keys"; then
        drop=true
    fi
    _update_session_file --arg old "$stamped" --arg new "$key" --arg l "$list" --argjson drop "$drop" \
        '.sessions = ((.sessions? // {}) | (if $drop and .[$old] == $l then del(.[$old]) else . end) + {($new): $l})'
    tmux set-option -wq -t "$id" @doit-window-key "$key" 2>/dev/null
done <<< "$windows"

[[ "$1" == "--migrate" && -f "$SESSION_FILE" ]] || exit 0
jq -e '(.sessions? // {}) | keys | any(contains(":") | not)' "$SESSION_FILE" &>/dev/null || exit 0
_update_session_file '.sessions |= with_entries(select(.key | contains(":")))'
