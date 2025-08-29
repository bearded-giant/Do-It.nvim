#!/bin/bash

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Build the Docker image
echo "Building Docker image..."
docker build -t doit-plugin-interactive .

# Create data directory
DATA_DIR="$HOME/.doit-data"
mkdir -p "$DATA_DIR"
mkdir -p "$DATA_DIR/doit/projects"
mkdir -p "$DATA_DIR/doit/notes"

# Initialize empty todos file if needed
if [ ! -f "$DATA_DIR/doit_todos.json" ] || [ ! -s "$DATA_DIR/doit_todos.json" ]; then
    echo "[]" >"$DATA_DIR/doit_todos.json"
    echo "Initialized empty todos file in $DATA_DIR"
fi

chmod -R 777 "$DATA_DIR"

clear

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║            Do-It.nvim Interactive Test Environment             ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# # Include the help documentation from the central file
# HELP_FILE="$SCRIPT_DIR/HELP.txt"
# if [ -f "$HELP_FILE" ]; then
#     cat "$HELP_FILE"
# else
#     echo "WARNING: Help file not found at $HELP_FILE"
#     echo "Basic commands: :DoIt, :DoItList, :DoItLists, :DoItNotes"
# fi

echo ""
echo "Data directory: $DATA_DIR"
echo ""
echo "Press Enter to start Neovim..."
read

docker run --rm -it \
    -v "$(pwd)/..:/plugin" \
    -v "$DATA_DIR:/data" \
    doit-plugin-interactive nvim

echo ""
echo "Session ended. Data saved to: $DATA_DIR"

