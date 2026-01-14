#!/usr/bin/env bash

# Do-It.nvim TPM entry point
# Sources the tmux integration from the tmux/ subdirectory

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/tmux/doit.tmux"
