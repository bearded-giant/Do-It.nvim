#!/bin/bash

cd "$(dirname "$0")"

docker build -t dooing-plugin-interactive .

DATA_DIR="$HOME/.dooing-data"
mkdir -p "$DATA_DIR"

if [ ! -f "$DATA_DIR/dooing_todos.json" ] || [ ! -s "$DATA_DIR/dooing_todos.json" ]; then
    echo "[]" >"$DATA_DIR/dooing_todos.json"
    echo "Initialized empty todos file in $DATA_DIR"
fi

chmod 666 "$DATA_DIR/dooing_todos.json"

echo "Using data directory: $DATA_DIR"
echo "Current todos file:"
cat "$DATA_DIR/dooing_todos.json"

docker run --rm -it \
    -v "$(pwd)/..:/plugin" \
    -v "$DATA_DIR:/data" \
    -v "$HOME/dotfiles/nvim/.config/nvim/lua/plugins/dooing.lua:/dooing-config.lua" \
    dooing-plugin-interactive nvim

echo "After Docker run, todos file:"
cat "$DATA_DIR/dooing_todos.json"
