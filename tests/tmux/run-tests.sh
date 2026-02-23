#!/bin/bash

# run all tmux bash tests
# usage: tests/tmux/run-tests.sh [specific_test.sh]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OVERALL_EXIT=0

if [[ -n "$1" ]]; then
    tests=("$SCRIPT_DIR/$1")
else
    tests=("$SCRIPT_DIR"/test_*.sh)
fi

for test_file in "${tests[@]}"; do
    [[ "$(basename "$test_file")" == "test_harness.sh" ]] && continue
    [[ ! -f "$test_file" ]] && continue

    echo ""
    echo "========================================"
    echo "Running: $(basename "$test_file")"
    echo "========================================"

    bash "$test_file"
    status=$?
    if [[ $status -ne 0 ]]; then
        OVERALL_EXIT=1
    fi
done

echo ""
if [[ $OVERALL_EXIT -eq 0 ]]; then
    echo "All test suites passed."
else
    echo "Some test suites failed."
fi
exit $OVERALL_EXIT
