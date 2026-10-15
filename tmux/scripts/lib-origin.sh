#!/bin/bash

# Mine / Claude classifier for every tmux script that orders or groups items;
# must agree with sorting.origin() in lua/doit/modules/todos/state/sorting.lua.
ORIGIN_JQ='
def origin:
    if (.source | type) == "string" and .source != "" then (if .source == "mcp" then "claude" else "mine" end)
    elif (.twin | type) == "object" then "claude"
    elif ((.text // "") | sub("^[ \\t\\n\\x0b\\f\\r]+"; "") | test("^(claude:|\\[[^\\]\\[]+\\]|[0-9]+[a-z]*\\.[ \\t\\n\\x0b\\f\\r])")) then "claude"
    else "mine" end;
def origin_rank: if (.done | not) and origin == "claude" then 1 else 0 end;
'
export ORIGIN_JQ
