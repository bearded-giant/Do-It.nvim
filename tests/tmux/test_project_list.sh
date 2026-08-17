#!/bin/bash

# Project-list derivation + the shared list-name sanitizer.
#
# The fixtures below are mirrored in tests/modules/todos/project_list_spec.lua.
# The two implementations (get-active-list.sh and state/project_list.lua) must
# agree, or one repo resolves to two different lists depending on which UI
# opened it and todos silently split across files.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_harness.sh"
source "$SCRIPT_DIR/../../tmux/scripts/get-active-list.sh"

describe "list name sanitizer"

check_sanitize() {
    it "sanitize '$1' -> '$2'"
    assert_eq "$2" "$(sanitize_list_name "$1")"
}

check_sanitize "do-it.nvim"        "do-it.nvim"        # dots survive: not "do-itnvim"
check_sanitize "my repo"           "my_repo"
check_sanitize "my   repo"         "my_repo"           # runs collapse to a single _
check_sanitize "a/b"               "ab"                # no path separators
check_sanitize "UPPER_case-1"      "UPPER_case-1"
check_sanitize ".."                ""                  # never a path traversal
check_sanitize "!!!"               ""
check_sanitize "chat-orchestrator" "chat-orchestrator"

describe "project list derivation"

TMPREPO="$TEST_TMPDIR/some.repo"
mkdir -p "$TMPREPO"
git -C "$TMPREPO" init -q 2>/dev/null

it "derives the list name from the git root basename"
assert_eq "some.repo" "$(derive_project_list "$TMPREPO")"

NOT_A_REPO="$TEST_TMPDIR/plain_dir"
mkdir -p "$NOT_A_REPO"

it "derives nothing outside a git repo"
DERIVED=$(derive_project_list "$NOT_A_REPO" 2>/dev/null || echo "")
assert_eq "" "$DERIVED"

report
