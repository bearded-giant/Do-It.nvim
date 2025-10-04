#!/bin/bash

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Build the Docker image quietly
docker build -t doit-plugin-interactive . > /dev/null 2>&1

# Create data directory
DATA_DIR="$HOME/.doit-data"
mkdir -p "$DATA_DIR"
mkdir -p "$DATA_DIR/doit/projects"
mkdir -p "$DATA_DIR/doit/notes"

# Initialize empty todos file if needed
if [ ! -f "$DATA_DIR/doit_todos.json" ] || [ ! -s "$DATA_DIR/doit_todos.json" ]; then
    echo "[]" >"$DATA_DIR/doit_todos.json"
fi

chmod -R 777 "$DATA_DIR"

docker run --rm -it \
    -v "$(pwd)/..:/plugin" \
    -v "$DATA_DIR:/data" \
    doit-plugin-interactive nvim
