#!/usr/bin/env bash

# Do-It.nvim Tmux Integration
# TPM plugin entry point

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$CURRENT_DIR/scripts"

# Export for use in status bar and other scripts
tmux set-environment -g DOIT_TMUX_DIR "$CURRENT_DIR"
tmux set-environment -g DOIT_SCRIPTS_DIR "$SCRIPTS_DIR"

# Set active list from session.json
if command -v jq &> /dev/null && [[ -f "$HOME/.local/share/nvim/doit/session.json" ]]; then
    ACTIVE_LIST=$(jq -r '.active_list // "daily"' "$HOME/.local/share/nvim/doit/session.json")
    tmux set-environment -g DOIT_ACTIVE_LIST "$ACTIVE_LIST"
fi

# Default keybinding prefix (can be overridden with @doit-key)
default_key="d"
doit_key=$(tmux show-option -gqv "@doit-key")
doit_key="${doit_key:-$default_key}"

# Set up the doit menu key table
tmux bind-key -T prefix "$doit_key" switch-client -T doit-menu

# Popup: quick view of todos (prefix + d + t)
tmux bind-key -T doit-menu t display-popup -E -w 75 -h 38 "$SCRIPTS_DIR/todo-popup.sh"

# Interactive manager with fzf (prefix + d + i)
tmux bind-key -T doit-menu i display-popup -E -w 120 -h 45 "$SCRIPTS_DIR/todo-interactive.sh"

# Toggle current todo done/undone (prefix + d + x)
tmux bind-key -T doit-menu x run-shell "$SCRIPTS_DIR/todo-toggle.sh"

# New todo (prefix + d + n)
tmux bind-key -T doit-menu n display-popup -E -w 80 -h 30 "$SCRIPTS_DIR/todo-create.sh"

# Start next pending todo (prefix + d + N)
tmux bind-key -T doit-menu N run-shell "$SCRIPTS_DIR/todo-next.sh"

# Switch todo list (prefix + d + l)
tmux bind-key -T doit-menu l display-popup -E -w 60 -h 20 "$SCRIPTS_DIR/todo-list-switch.sh"

# List manager - create/rename/delete (prefix + d + L)
tmux bind-key -T doit-menu L display-popup -E -w 70 -h 25 "$SCRIPTS_DIR/todo-list-manager.sh"

# Editor mode for create/edit (default: off, uses inline input)
# Set to "true" to use $EDITOR (nvim, vim, etc) instead
# set -g @doit-use-editor "true"

# Note popup dimensions (default: 80x20)
# set -g @doit-note-popup-w "80"
# set -g @doit-note-popup-h "20"

# Alt+Shift shortcuts (no prefix needed)
# Check if alt bindings are enabled (default: yes)
alt_bindings=$(tmux show-option -gqv "@doit-alt-bindings")
if [[ "$alt_bindings" != "off" ]]; then
    tmux bind-key -n M-T display-popup -E -w 75 -h 38 "$SCRIPTS_DIR/todo-popup.sh"
    tmux bind-key -n M-I display-popup -E -w 120 -h 45 "$SCRIPTS_DIR/todo-interactive.sh"
    tmux bind-key -n M-X run-shell "$SCRIPTS_DIR/todo-toggle.sh"
    tmux bind-key -n M-N display-popup -E -w 80 -h 30 "$SCRIPTS_DIR/todo-create.sh"
    tmux bind-key -n M-L display-popup -E -w 60 -h 20 "$SCRIPTS_DIR/todo-list-switch.sh"
fi
