#!/bin/bash

# Machine-managed "last modified" footer for todo descriptions. Shared by the
# create/edit paths so the format lives in one place.

# Drop the footer so editing shows body only and re-saving refreshes rather
# than stacks. Matches either verb so older "last updated" stamps are stripped.
strip_footer() {
    awk 'BEGIN{RS="\0"} {sub(/\n*----------\nlast (updated|modified):[^\n]*\n*$/,""); printf "%s",$0}' <<< "$1"
}

# Append a fresh footer. Body may be empty (footer-only) — every todo carries a stamp.
stamp_description() {
    printf '%s\n\n\n----------\nlast modified: %s' "$(strip_footer "$1")" "$(date '+%Y-%m-%d: %H:%M')"
}
