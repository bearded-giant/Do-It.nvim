#!/bin/bash

# minimal bash test harness for tmux script testing
# usage: source this file, then call test functions

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
FAILURES=""

# temp dir for test fixtures, cleaned up on exit
TEST_TMPDIR=$(mktemp -d /tmp/doit-test.XXXXXX)
trap 'rm -rf "$TEST_TMPDIR"' EXIT

color_green=$'\e[32m'
color_red=$'\e[31m'
color_reset=$'\e[0m'

describe() {
    echo ""
    echo "== $1 =="
}

it() {
    CURRENT_TEST="$1"
}

assert_eq() {
    local expected="$1"
    local actual="$2"
    local msg="${3:-expected '$expected', got '$actual'}"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$expected" == "$actual" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  ${color_green}pass${color_reset}: $CURRENT_TEST"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  ${color_red}FAIL${color_reset}: $CURRENT_TEST"
        echo "        $msg"
        FAILURES="${FAILURES}\n  - $CURRENT_TEST: $msg"
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local msg="${3:-output does not contain '$needle'}"
    TESTS_RUN=$((TESTS_RUN + 1))
    if echo "$haystack" | grep -qF -- "$needle"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  ${color_green}pass${color_reset}: $CURRENT_TEST"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  ${color_red}FAIL${color_reset}: $CURRENT_TEST"
        echo "        $msg"
        FAILURES="${FAILURES}\n  - $CURRENT_TEST: $msg"
    fi
}

assert_file_contains() {
    local file="$1"
    local needle="$2"
    local msg="${3:-file $file does not contain '$needle'}"
    TESTS_RUN=$((TESTS_RUN + 1))
    if grep -qF -- "$needle" "$file"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  ${color_green}pass${color_reset}: $CURRENT_TEST"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  ${color_red}FAIL${color_reset}: $CURRENT_TEST"
        echo "        $msg"
        FAILURES="${FAILURES}\n  - $CURRENT_TEST: $msg"
    fi
}

assert_not_empty() {
    local val="$1"
    local msg="${3:-value is empty}"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ -n "$val" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  ${color_green}pass${color_reset}: $CURRENT_TEST"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  ${color_red}FAIL${color_reset}: $CURRENT_TEST"
        echo "        $msg"
        FAILURES="${FAILURES}\n  - $CURRENT_TEST: $msg"
    fi
}

assert_file_line() {
    local file="$1"
    local line_num="$2"
    local expected="$3"
    local actual
    actual=$(sed -n "${line_num}p" "$file")
    local msg="${4:-line $line_num: expected '$expected', got '$actual'}"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$expected" == "$actual" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  ${color_green}pass${color_reset}: $CURRENT_TEST"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  ${color_red}FAIL${color_reset}: $CURRENT_TEST"
        echo "        $msg"
        FAILURES="${FAILURES}\n  - $CURRENT_TEST: $msg"
    fi
}

report() {
    echo ""
    echo "──────────────────────────────────────"
    echo "Results: $TESTS_PASSED/$TESTS_RUN passed, $TESTS_FAILED failed"
    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo ""
        echo "Failures:"
        echo -e "$FAILURES"
        echo ""
        exit 1
    fi
    echo ""
    exit 0
}
