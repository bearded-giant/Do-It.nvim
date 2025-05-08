# Command Registration Fixes for Interactive Mode

## Problem

In the interactive mode (`docker/run-interactive.sh`), the `:DoItNotes` command was failing to work properly. This was happening because of how commands were registered with the Neovim command system across different loading modes.

## Solution

1. Created a `register_module_commands()` function in the main `doit.init.lua` file to ensure that all module commands are properly registered regardless of how the plugin is loaded.

2. Implemented core command handlers that check for both module-based and legacy implementations:
   - DoIt - Opens the main todo window
   - DoItList - Opens the quick todo list window
   - DoItNotes - Opens the notes interface
   - DoItLists - Manages todo lists

3. Updated the plugin initialization in `plugin/doit.vim` to explicitly call the command registration function after setup.

4. Added a test for the command registration functionality.

## Implementation Notes

The key issue was that in the framework mode, commands would be registered through the module system, but in standalone mode or with the Docker interactive environment, this registration might not happen correctly. The solution ensures all essential commands are always available.

The command registration system now:
1. Checks if a command already exists before creating it
2. Creates fallback paths for both module-based and legacy implementation
3. Provides helpful error messages if a module isn't available

This ensures a consistent command interface regardless of how the plugin is loaded or which modules are enabled.