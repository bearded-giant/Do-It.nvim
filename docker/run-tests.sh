#!/bin/bash

cd "$(dirname "$0")"
docker build -t doit-plugin-test .
docker run --rm -v "$(pwd)/..:/plugin" doit-plugin-test nvim --headless -c "lua require('plenary.test_harness').test_directory('tests', {pattern = '.*_spec.lua', recursive = true})" -c "qa!"

# For interactive testing, uncomment:
# docker run --rm -it -v "$(pwd)/..:/plugin" doit-plugin-test nvim
