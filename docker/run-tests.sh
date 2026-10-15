#!/bin/bash

cd "$(dirname "$0")"

# Build the Docker image
docker build -t doit-plugin-test .

TEST_PATTERN=""
TEST_DIR="tests"

# Check if specific test pattern was requested
if [ "$1" == "--pattern" ] && [ -n "$2" ]; then
    TEST_PATTERN="$2"
    shift 2
fi

# Check if specific test directory was requested
if [ "$1" == "--dir" ] && [ -n "$2" ]; then
    TEST_DIR="$2"
    shift 2
fi

# plenary's test_directory has no pattern option but takes a single spec file,
# so --pattern resolves to the matching files up front
TARGETS="$TEST_DIR"
if [ -n "$TEST_PATTERN" ]; then
    TARGETS=$(cd .. && find "$TEST_DIR" -type f -name '*_spec.lua' -path "*$TEST_PATTERN*" | sort)
    if [ -z "$TARGETS" ]; then
        echo "No spec files under '$TEST_DIR' match '$TEST_PATTERN'"
        exit 1
    fi
fi

TEST_CMD="cd /plugin"
for target in $TARGETS; do
    TEST_CMD="$TEST_CMD; nvim --headless -c \"lua require('plenary.test_harness').test_directory('$target')\" -c \"qa!\""
done

echo "Running tests in: $(echo $TARGETS)"
echo "Test command: $TEST_CMD"

# per-run log, so two runs at once don't read each other's results
LOG_FILE=$(mktemp "${TMPDIR:-/tmp}/doit-test-output.XXXXXX")
trap 'rm -f "$LOG_FILE"' EXIT

# Run with a timeout that kills the container after 60 seconds
container_id=$(docker run -d -v "$(pwd)/..:/plugin" doit-plugin-test sh -c "$TEST_CMD")

# Follow logs in background while container runs
echo "Running tests..."
docker logs -f $container_id > "$LOG_FILE" 2>&1 &
log_pid=$!

# Wait for container to finish (with 60 second timeout)
timeout 60 docker wait $container_id > /dev/null 2>&1
wait_result=$?

# Kill the log following process
kill $log_pid > /dev/null 2>&1 || true
wait $log_pid > /dev/null 2>&1 || true

# Check if timeout occurred
if [ $wait_result -eq 124 ]; then
  echo "Test execution timed out. Killing container..."
  docker kill $container_id > /dev/null 2>&1
  docker rm $container_id > /dev/null 2>&1
  exit 1
fi

# Show the logs
cat "$LOG_FILE"

# Check for test failures in output
if grep -q "Tests Failed\." "$LOG_FILE"; then
  echo "Tests failed! See output above for details"
  docker rm $container_id > /dev/null 2>&1
  exit 1
fi

# Check for errors
if grep -q "Errors : [1-9]" "$LOG_FILE"; then
  echo "Tests had errors!"
  docker rm $container_id > /dev/null 2>&1
  exit 1
fi

# Clean up
docker rm $container_id > /dev/null 2>&1

echo "All tests passed!"
exit 0

# For interactive testing:
# docker run --rm -it -v "$(pwd)/..:/plugin" doit-plugin-test nvim