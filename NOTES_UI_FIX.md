# Notes UI Fix for Docker Interactive Mode

## Problem

When running in the Docker interactive mode (`docker/run-interactive.sh`), the `:DoItNotes` command was failing with the following error:

```
Error executing Lua callback: /plugin/lua/doit/core/ui/init.lua:28: attempt to index field 'window' (a nil value)
stack traceback:
    /plugin/lua/doit/core/ui/init.lua:28: in function 'create_buffer'
    /plugin/lua/doit/modules/notes/ui/notes_window.lua:35: in function 'create_buf'
    /plugin/lua/doit/modules/notes/ui/notes_window.lua:227: in function 'toggle_notes_window'
    /plugin/lua/doit/modules/notes/commands.lua:11: in function </plugin/lua/doit/modules/notes/commands.lua:10>
```

## Root Cause

1. The core UI module (`core.ui`) was being imported but its `setup()` function was not being called during initialization.

2. As a result, the `window` component was never assigned to `core.ui`, causing the error when trying to access `core.ui.window` functions.

## Solution

The fix involves two parts:

1. **Core UI Initialization Fix**: Added `.setup()` call to the UI module during initialization in `doit/core/init.lua`.

2. **Defensive Coding**: Added additional safeguards in the notes window implementation to check if `core.ui.window` exists before attempting to use its functions.

## Implementation Details

1. Updated the core initialization to properly setup the UI module:
   ```lua
   -- Initialize UI utilities
   M.ui = require("doit.core.ui").setup()
   ```

2. Added defensive checks in the notes window UI code:
   ```lua
   if core and core.ui and core.ui.window then
       -- Use core.ui functions
   else
       -- Fallback to direct nvim API
   end
   ```

3. These changes ensure that the notes window will work correctly regardless of how the plugin is loaded or whether the core UI components are fully initialized.

## Benefits

1. More robust code that can handle different loading environments.
2. Better error handling and graceful fallbacks.
3. Fixed the `:DoItNotes` command in the Docker interactive environment.