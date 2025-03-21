#!/bin/bash

# Change to the docker directory
cd "$(dirname "$0")"

# Build the Docker image if needed
docker build -t dooing-plugin-interactive .

# Create a data directory in user's home that will persist
DATA_DIR="$HOME/.dooing-data"
mkdir -p "$DATA_DIR"

# Initialize JSON file if needed
if [ ! -f "$DATA_DIR/dooing_todos.json" ] || [ ! -s "$DATA_DIR/dooing_todos.json" ]; then
  echo "[]" > "$DATA_DIR/dooing_todos.json"
  echo "Initialized empty todos file in $DATA_DIR"
fi

# Ensure file permissions are correct
chmod 666 "$DATA_DIR/dooing_todos.json"

echo "Using data directory: $DATA_DIR"
echo "Current todos file:"
cat "$DATA_DIR/dooing_todos.json"

# Run interactive Neovim session with mounted home directory for persistence
docker run --rm -it \
  -v "$(pwd)/..:/plugin" \
  -v "$DATA_DIR:/data" \
  -v "$HOME/dotfiles/nvim/.config/nvim/lua/plugins/dooing.lua:/dooing-config.lua" \
  dooing-plugin-interactive nvim

echo "After Docker run, todos file:"
cat "$DATA_DIR/dooing_todos.json"
