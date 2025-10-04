#!/bin/bash

# Run obsidian-sync module tests

echo "Running obsidian-sync tests..."
echo "=============================="

# Run with plenary test harness
nvim --headless \
  -c "lua require('plenary.test_harness').test_directory('tests/modules/obsidian-sync', {minimal_init='tests/minimal_init.vim'})" \
  -c "qa!"

# Check exit code
if [ $? -eq 0 ]; then
  echo "✓ All tests passed!"
else
  echo "✗ Some tests failed"
  exit 1
fi