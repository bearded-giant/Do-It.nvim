#!/bin/bash

cd "$(dirname "$0")"

# Build the Docker image
docker build -t doit-plugin-test .

# Default test pattern
TEST_PATTERN=".*_spec.lua"
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

# Create test command
TEST_CMD="cd /plugin && nvim --headless -c \"lua require('plenary.test_harness').test_directory('$TEST_DIR', {pattern = '$TEST_PATTERN', recursive = true})\" -c \"qa!\""

echo "Running tests with pattern '$TEST_PATTERN' in directory '$TEST_DIR'"
echo "Test command: $TEST_CMD"

# Run with a timeout that kills the container after 60 seconds
container_id=$(docker run -d -v "$(pwd)/..:/plugin" doit-plugin-test sh -c "$TEST_CMD")

# Follow logs in background while container runs
echo "Running tests..."
docker logs -f $container_id > /tmp/test_output.log 2>&1 &
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
cat /tmp/test_output.log

# Check for test failures in output
if grep -q "Tests Failed\." /tmp/test_output.log; then
  echo "Tests failed! See output above for details"
  docker rm $container_id > /dev/null 2>&1
  exit 1
fi

# Check for errors
if grep -q "Errors : [1-9]" /tmp/test_output.log; then
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