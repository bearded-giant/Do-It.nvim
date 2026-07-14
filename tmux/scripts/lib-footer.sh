#!/bin/bash

# Machine-managed "last modified" footer for todo descriptions. Shared by the
# create/edit paths so the format lives in one place.

# Drop the footer so editing shows body only and re-saving refreshes rather
# than stacks. Matches either verb so older "last updated" stamps are stripped.
# Pure bash: macOS awk reads RS="\0" as paragraph mode and eats every blank line.
strip_footer() {
    local s="$1" nl=$'\n'
    local re="${nl}*----------${nl}last (updated|modified):[^${nl}]*${nl}*\$"
    [[ "$s" =~ $re ]] && s="${s%"${BASH_REMATCH[0]}"}"
    printf '%s' "$s"
}

# Append a fresh footer. Body may be empty (footer-only) — every todo carries a stamp.
stamp_description() {
    printf '%s\n\n\n----------\nlast modified: %s' "$(strip_footer "$1")" "$(date '+%Y-%m-%d: %H:%M')"
}
