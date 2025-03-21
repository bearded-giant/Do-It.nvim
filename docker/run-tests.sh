#!/bin/bash

cd "$(dirname "$0")"
docker build -t dooing-plugin-test .
docker run --rm -v "$(pwd)/..:/plugin" dooing-plugin-test nvim --headless -c "lua require('plenary.test_harness').test_directory('tests', {pattern = '.*_spec.lua', recursive = true})" -c "qa!"

# For interactive testing, uncomment:
# docker run --rm -it -v "$(pwd)/..:/plugin" dooing-plugin-test nvim

