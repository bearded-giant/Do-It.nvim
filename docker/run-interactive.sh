#!/bin/bash

cd "$(dirname "$0")"

echo "Building interactive container with DAP support..."
docker build -t doit-plugin-interactive .

DATA_DIR="$HOME/.doit-data"
mkdir -p "$DATA_DIR"

if [ ! -f "$DATA_DIR/doit_todos.json" ] || [ ! -s "$DATA_DIR/doit_todos.json" ]; then
    echo "[]" >"$DATA_DIR/doit_todos.json"
    echo "Initialized empty todos file in $DATA_DIR"
fi

chmod 666 "$DATA_DIR/doit_todos.json"

echo "Using data directory: $DATA_DIR"
echo "Current todos file:"
cat "$DATA_DIR/doit_todos.json"

# Get absolute path to plugin directory for proper path mappings
PLUGIN_DIR=$(cd "$(pwd)/.." && pwd)
echo "Plugin directory: $PLUGIN_DIR"

echo -e "\n\033[1;32m======== DEBUGGING INSTRUCTIONS ========\033[0m"
echo -e "1. Use '\033[1;36m<leader>ds\033[0m' to start the debugger server"
echo -e "2. Set breakpoints with '\033[1;36m<leader>db\033[0m' on lines you want to debug"
echo -e "3. Use '\033[1;36m<leader>dc\033[0m' to continue execution until a breakpoint is hit"

echo -e "\n\033[1;33m--- WHEN BREAKPOINT IS HIT ---\033[0m"
echo -e "• The plugin window will automatically move to make space for debugging info"
echo -e "• View variables with '\033[1;36m<leader>dv\033[0m' (shows scopes in floating window)"
echo -e "• Toggle full UI with '\033[1;36m<leader>du\033[0m'"
echo -e "• Restore plugin window position with '\033[1;36m<leader>dr\033[0m'"
echo -e "• Step with '\033[1;36m<leader>dsi\033[0m' (into), '\033[1;36m<leader>dso\033[0m' (over), '\033[1;36m<leader>dx\033[0m' (out)"

echo -e "\n\033[1;33m--- PLUGIN WINDOW COMMANDS ---\033[0m"
echo -e "• While debugging, your plugin window will be resized and moved to the left"
echo -e "• You can toggle between debug and plugin using keyboard shortcuts"
echo -e "• After debugging, restore window with '\033[1;36m<leader>dr\033[0m'"

echo -e "\n\033[1;31m--- EMERGENCY ESCAPE ---\033[0m"
echo -e "• If everything is stuck, press '\033[1;36m<leader>dX\033[0m' or type '\033[1;36m:DebugEmergencyExit\033[0m'"
echo -e "• This will close both plugin and debugger windows"
echo -e "• As a last resort, press Ctrl+C in terminal to kill neovim"
echo -e "\033[1;32m======================================\033[0m\n"

docker run --rm -it -p 8086:8086 \
    -v "$PLUGIN_DIR:/plugin" \
    -v "$PLUGIN_DIR:/host-plugin" \
    -v "$DATA_DIR:/data" \
    -v "$HOME/dotfiles/nvim/.config/nvim/lua/plugins/doit.lua:/doit-config.lua" \
    doit-plugin-interactive nvim

echo "After Docker run, todos file:"
cat "$DATA_DIR/doit_todos.json"
